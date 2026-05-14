import Foundation
import CoreData

extension CLIBridge {
    /// Value-type bag for the filter flags shared by `ls`, `count`, `watch`,
    /// `filters run --inline`. Built up by argument-parser command structs
    /// and translated to a Plan 3 `PredicateGroup` via `toPredicateGroup`.
    ///
    /// `toPredicateGroup` is `async throws` because tag-name → UUID
    /// resolution requires a `PersistenceController` lookup against
    /// `TagStore`. Tag-name lookups that find nothing produce an empty
    /// uuidSet leaf — semantically "no tasks match" — rather than throwing,
    /// so `lillist ls --tag UnknownTag` silently returns zero rows.
    public struct FilterFlags: Sendable, Equatable {
        public var combinator: PredicateGroup.Combinator = .all
        public var tags: [String] = []
        public var excludeTags: [String] = []
        public var statuses: [Status] = []
        public var deadlineBefore: String?
        public var deadlineAfter: String?
        public var startBefore: String?
        public var startAfter: String?
        public var hasAttachments: Bool = false
        public var pinned: Bool = false
        public var includeTrash: Bool = false

        public init() {}

        /// Translates the flags into a `PredicateGroup`.
        ///
        /// `applyTrashImplicit` adds the implicit `inTrash is false` predicate
        /// unless `includeTrash` is set. Verbs that want to query the Trash
        /// directly (e.g. `restore`) pass `applyTrashImplicit: false`.
        public func toPredicateGroup(
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar,
            applyTrashImplicit: Bool = true
        ) async throws -> PredicateGroup {
            var predicates: [Predicate] = []

            if tags.isEmpty == false {
                let ids = try await Self.tagIDs(for: tags, persistence: persistence)
                predicates.append(.leaf(.init(field: .tag, op: .includesAny, value: .uuidSet(ids))))
            }
            if excludeTags.isEmpty == false {
                let ids = try await Self.tagIDs(for: excludeTags, persistence: persistence)
                predicates.append(.leaf(.init(field: .tag, op: .excludesAll, value: .uuidSet(ids))))
            }
            if statuses.isEmpty == false {
                predicates.append(.leaf(.init(field: .status, op: .is, value: .statusSet(Set(statuses)))))
            }
            if let s = deadlineBefore {
                let d = try DateParsing.parse(s, now: now, calendar: calendar)
                predicates.append(.leaf(.init(field: .deadline, op: .before, value: .absoluteDate(d.date))))
            }
            if let s = deadlineAfter {
                let d = try DateParsing.parse(s, now: now, calendar: calendar)
                predicates.append(.leaf(.init(field: .deadline, op: .after, value: .absoluteDate(d.date))))
            }
            if let s = startBefore {
                let d = try DateParsing.parse(s, now: now, calendar: calendar)
                predicates.append(.leaf(.init(field: .start, op: .before, value: .absoluteDate(d.date))))
            }
            if let s = startAfter {
                let d = try DateParsing.parse(s, now: now, calendar: calendar)
                predicates.append(.leaf(.init(field: .start, op: .after, value: .absoluteDate(d.date))))
            }
            if hasAttachments {
                predicates.append(.leaf(.init(
                    field: .hasAttachments,
                    op: .is,
                    value: .attachmentKind(AttachmentKindMatch(present: true, kind: nil))
                )))
            }
            if pinned {
                predicates.append(.leaf(.init(field: .isPinned, op: .is, value: .bool(true))))
            }
            if applyTrashImplicit && includeTrash == false {
                predicates.append(.leaf(.init(field: .inTrash, op: .is, value: .bool(false))))
            }

            return PredicateGroup(combinator: combinator, predicates: predicates)
        }

        /// Resolves a list of tag names into a `Set<UUID>` of matching tag IDs.
        /// Names that don't match anything are silently dropped (yielding a
        /// uuidSet that excludes them). This is the design's intended fallback
        /// for `lillist ls --tag UnknownTag` — empty result, not an error.
        static func tagIDs(for names: [String], persistence: PersistenceController) async throws -> Set<UUID> {
            let ctx = persistence.container.viewContext
            return try await ctx.perform {
                let req = NSFetchRequest<Tag>(entityName: "Tag")
                let lower = Set(names.map { $0.lowercased() })
                let all = try ctx.fetch(req)
                let hits = all.filter { tag in
                    guard let n = tag.name else { return false }
                    return lower.contains(n.lowercased())
                }
                return Set(hits.compactMap(\.id))
            }
        }
    }
}
