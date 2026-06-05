import Foundation
import CoreData

extension CLIBridge {
    /// Resolves a user-supplied token to a single task ID per design Section 6
    /// ("Fuzzy task resolution"):
    ///
    /// 1. If the token matches `^[0-9a-f]{4,}$`, treat as a UUID prefix.
    /// 2. Otherwise, case- and diacritic-insensitive substring match on title
    ///    (via `localizedStandardContains`).
    /// 3. Exact (case-insensitive) title match wins over substring.
    /// 4. Default scope excludes trashed and closed tasks.
    /// 5. Multiple matches throw `.ambiguous([candidateIDs])`.
    /// 6. Destructive verbs require UUID or exact match; partial matches throw.
    public enum Resolver {
        public enum Scope: Sendable {
            case anywhere
            case anywhereIncludingClosed
            case descendantsOf(UUID)
            case descendantsOfIncludingClosed(UUID)
        }

        public enum Destructiveness: Sendable {
            /// Read-only verbs accept best-effort substring matches.
            case readOnly
            /// Destructive verbs (delete, purge, move, status→closed, restore)
            /// require UUID or exact title match.
            case destructive
        }

        public enum MatchKind: Sendable, Equatable {
            case uuidExact
            case uuidPrefix
            case exactTitle
            case substring
        }

        public struct Resolution: Sendable, Equatable {
            public let id: UUID
            public let matchKind: MatchKind
            /// True when the matcher had to pick among multiple options (e.g.
            /// non-unique substring). Callers may emit a stderr note.
            public let pickedSilently: Bool
        }

        /// Resolves a single token to one task.
        public static func resolve(
            token: String,
            scope: Scope,
            destructiveness: Destructiveness,
            persistence: PersistenceController
        ) async throws -> Resolution {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw LillistError.validationFailed([.init(field: "task", message: "token is empty")])
            }

            // UUID full or prefix routing.
            if let full = UUID(uuidString: trimmed) {
                return try await resolveExactUUID(full, scope: scope, persistence: persistence)
            }
            if looksLikeHexPrefix(trimmed) {
                return try await resolveUUIDPrefix(trimmed, scope: scope, persistence: persistence)
            }

            // Title path.
            let candidates = try await fetchTitleCandidates(token: trimmed, scope: scope, persistence: persistence)
            guard candidates.isEmpty == false else { throw LillistError.notFound }

            // Exact (case-insensitive) match wins.
            let lower = trimmed.lowercased()
            let exact = candidates.filter { $0.title.lowercased() == lower }
            if exact.count == 1 {
                return Resolution(id: exact[0].id, matchKind: .exactTitle, pickedSilently: false)
            }
            if exact.count > 1 {
                throw LillistError.ambiguous(exact.map(\.id))
            }

            // Substring path.
            if candidates.count == 1 {
                if destructiveness == .destructive {
                    throw LillistError.validationFailed([
                        .init(field: "task", message: "destructive verbs require a UUID or exact title; '\(trimmed)' only partially matched. Pass the full title or the task's UUID (run `lillist ls` to find it).")
                    ])
                }
                return Resolution(id: candidates[0].id, matchKind: .substring, pickedSilently: true)
            }

            throw LillistError.ambiguous(candidates.map(\.id))
        }

        /// Resolves every token to a concrete `Resolution` *before* any caller
        /// mutates. This is the all-or-nothing primitive for destructive stdin
        /// batches: if any token is unresolvable (`.notFound`/`.ambiguous`) or
        /// refused (destructive partial match), this throws and the caller has
        /// performed zero mutations. Resolutions are returned in token order.
        public static func resolveAll(
            tokens: [String],
            scope: Scope,
            destructiveness: Destructiveness,
            persistence: PersistenceController
        ) async throws -> [Resolution] {
            var resolutions: [Resolution] = []
            resolutions.reserveCapacity(tokens.count)
            for token in tokens {
                let resolution = try await resolve(
                    token: token,
                    scope: scope,
                    destructiveness: destructiveness,
                    persistence: persistence
                )
                resolutions.append(resolution)
            }
            return resolutions
        }

        /// Computes the shortest UUID prefix (lowercased, no dashes) that uniquely
        /// identifies each ID among the given set. Minimum length 4 chars.
        public static func shortestUniqueShortIDs(_ ids: [UUID], minLength: Int = 4) -> [UUID: String] {
            let normalized = ids.map { (id: $0, hex: $0.uuidString.lowercased().replacingOccurrences(of: "-", with: "")) }
            var result: [UUID: String] = [:]
            for (id, hex) in normalized {
                var length = max(minLength, 4)
                while length <= hex.count {
                    let prefix = String(hex.prefix(length))
                    let collisions = normalized.filter { $0.hex.hasPrefix(prefix) && $0.id != id }
                    if collisions.isEmpty {
                        result[id] = prefix
                        break
                    }
                    length += 1
                }
                if result[id] == nil { result[id] = hex }
            }
            return result
        }

        // MARK: - Internals

        struct Candidate: Sendable, Equatable {
            let id: UUID
            let title: String
        }

        /// Diacritic- and case-insensitive substring match.
        ///
        /// `localizedStandardContains` does case folding but not diacritic
        /// folding in every locale, and `String.range(of:options:)` with
        /// `.diacriticInsensitive` requires the contents to be byte-aligned
        /// to fold. The robust path is to fold both sides via
        /// `applyingTransform(.stripDiacritics, …)` (Unicode-aware) and then
        /// case-fold via `lowercased()` before substring testing.
        static func foldedContains(haystack: String, needle: String) -> Bool {
            let foldedHaystack = (haystack.applyingTransform(.stripDiacritics, reverse: false) ?? haystack).lowercased()
            let foldedNeedle = (needle.applyingTransform(.stripDiacritics, reverse: false) ?? needle).lowercased()
            return foldedHaystack.contains(foldedNeedle)
        }

        static func looksLikeHexPrefix(_ s: String) -> Bool {
            guard s.count >= 4 else { return false }
            let set = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            return s.unicodeScalars.allSatisfy { set.contains($0) }
        }

        static func resolveExactUUID(
            _ id: UUID,
            scope: Scope,
            persistence: PersistenceController
        ) async throws -> Resolution {
            let ctx = persistence.container.viewContext
            return try await ctx.perform {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = sqlPredicate(scope: scope, base: NSPredicate(format: "id == %@", id as CVarArg))
                let results = try ctx.fetch(req).filter { passesScope($0, scope: scope) }
                guard let m = results.first, let mid = m.id else {
                    throw LillistError.notFound
                }
                return Resolution(id: mid, matchKind: .uuidExact, pickedSilently: false)
            }
        }

        static func resolveUUIDPrefix(
            _ prefix: String,
            scope: Scope,
            persistence: PersistenceController
        ) async throws -> Resolution {
            let ctx = persistence.container.viewContext
            return try await ctx.perform {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = sqlPredicate(scope: scope, base: nil)
                let all = try ctx.fetch(req).filter { passesScope($0, scope: scope) }
                let lower = prefix.lowercased()
                let matches = all.filter { task in
                    guard let id = task.id else { return false }
                    return id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").hasPrefix(lower)
                }
                if matches.isEmpty { throw LillistError.notFound }
                if matches.count == 1, let id = matches[0].id {
                    return Resolution(id: id, matchKind: .uuidPrefix, pickedSilently: false)
                }
                throw LillistError.ambiguous(matches.compactMap(\.id))
            }
        }

        static func fetchTitleCandidates(
            token: String,
            scope: Scope,
            persistence: PersistenceController
        ) async throws -> [Candidate] {
            let ctx = persistence.container.viewContext
            return try await ctx.perform {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = sqlPredicate(scope: scope, base: nil)
                let all = try ctx.fetch(req).filter { passesScope($0, scope: scope) }
                let matches = all.filter { task in
                    guard let title = task.title else { return false }
                    return foldedContains(haystack: title, needle: token)
                }
                return matches.compactMap { task in
                    guard let id = task.id, let title = task.title else { return nil }
                    return Candidate(id: id, title: title)
                }
            }
        }

        /// Builds a Core Data SQL-friendly predicate covering the parts of `scope`
        /// that translate cleanly to SQL: `deletedAt == nil` and the
        /// not-closed / closed-included split. Descendant scope is enforced
        /// in-memory by `passesScope` because parent-chain traversal cannot be
        /// expressed against a SQL store.
        ///
        /// `base` is AND'd in (used by full-UUID resolution).
        static func sqlPredicate(scope: Scope, base: NSPredicate?) -> NSPredicate {
            var parts: [NSPredicate] = []
            if let base { parts.append(base) }
            parts.append(NSPredicate(format: "deletedAt == nil"))
            switch scope {
            case .anywhere, .descendantsOf:
                parts.append(NSPredicate(format: "statusRaw != %d", Status.closed.rawValue))
            case .anywhereIncludingClosed, .descendantsOfIncludingClosed:
                break
            }
            return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
        }

        /// Post-fetch filter that enforces the descendant-of-root constraint
        /// (which cannot be expressed against a SQL store via NSPredicate).
        static func passesScope(_ task: LillistTask, scope: Scope) -> Bool {
            switch scope {
            case .anywhere, .anywhereIncludingClosed:
                return true
            case .descendantsOf(let rootID), .descendantsOfIncludingClosed(let rootID):
                var cursor: LillistTask? = task.parent
                var depth = 0
                while let node = cursor, depth < PredicateLimits.maxAncestorDepth {
                    if node.id == rootID { return true }
                    cursor = node.parent
                    depth += 1
                }
                return false
            }
        }
    }
}
