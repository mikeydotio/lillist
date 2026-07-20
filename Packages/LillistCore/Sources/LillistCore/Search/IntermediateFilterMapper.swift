import Foundation

/// Converts an `IntermediateFilter` (a translator's flat, natural-language
/// output) into a real `PredicateGroup`, enforcing the same Field × Op ×
/// Value compatibility matrix that `NSPredicateCompiler` and `SwiftEvaluator`
/// already enforce — so a translator can never produce a leaf that silently
/// evaluates `false` in both engines without anyone knowing why. This is the
/// one and only path from natural language to an executable `PredicateGroup`
/// (see `FilterQueryTranslator`'s default `translate(_:context:)`), and the
/// most heavily tested type in the agentic-search feature.
///
/// Mapping never throws: a clause the mapper can't place is reported in
/// `MappingResult.dropped` instead (per-clause tolerance), so one bad clause
/// doesn't sink an otherwise-good query.
public enum IntermediateFilterMapper {
    public static func map(_ filter: IntermediateFilter, context: TranslationContext) -> MappingResult {
        var leaves: [Predicate] = []
        var dropped: [DroppedClause] = []
        var unresolvedTagNames: Set<String> = []

        for clause in filter.clauses {
            switch resolve(clause, context: context) {
            case .leaf(let leaf):
                leaves.append(.leaf(leaf))
            case .leafWithUnresolvedTags(let leaf, let names):
                leaves.append(.leaf(leaf))
                unresolvedTagNames.formUnion(names)
            case .dropped(let reason):
                dropped.append(DroppedClause(field: clause.field, op: clause.op, reason: reason))
            }
        }

        return MappingResult(
            group: PredicateGroup(combinator: filter.combinator, predicates: leaves),
            dropped: dropped,
            unresolvedTagNames: unresolvedTagNames.sorted()
        )
    }

    // MARK: - Per-clause resolution

    private enum Resolution {
        case leaf(Leaf)
        case leafWithUnresolvedTags(Leaf, [String])
        case dropped(DropReason)
    }

    private static func resolve(_ clause: IntermediateClause, context: TranslationContext) -> Resolution {
        switch clause.field {
        case .title, .notes, .journalText:
            return resolveStringLike(clause)
        case .status:
            return resolveStatus(clause)
        case .isPinned, .hasChildren, .hasNudges, .recurrence, .inTrash:
            return resolveBoolean(clause)
        case .tag:
            return resolveTag(clause, context: context)
        case .start, .deadline, .createdAt, .modifiedAt, .closedAt:
            return resolveDate(clause)
        case .hasAttachments:
            return resolveAttachments(clause)
        case .ancestor:
            // No natural-language phrase maps to ancestor scoping today, and
            // `isAncestorOf` is a deliberate `false` stub in both engines
            // (YAGNI, per `NSPredicateCompiler.compileAncestor`) — treat the
            // whole field as off-matrix from a translator's perspective
            // rather than emitting a leaf that quietly always fails.
            return .dropped(.offMatrix)
        }
    }

    private static let stringLikeOps: [Field: Set<Op>] = [
        .title: [.contains, .equals, .startsWith],
        .notes: [.contains, .equals, .startsWith],
        .journalText: [.contains]
    ]

    private static func resolveStringLike(_ clause: IntermediateClause) -> Resolution {
        guard case .text(let s) = clause.value else { return .dropped(.wrongValueKind) }
        guard let allowed = stringLikeOps[clause.field], allowed.contains(clause.op) else {
            return .dropped(.offMatrix)
        }
        return .leaf(Leaf(field: clause.field, op: clause.op, value: .string(s)))
    }

    private static func resolveStatus(_ clause: IntermediateClause) -> Resolution {
        guard clause.op == .is || clause.op == .isNot else { return .dropped(.offMatrix) }
        guard case .statuses(let statuses) = clause.value, !statuses.isEmpty else {
            return .dropped(.wrongValueKind)
        }
        return .leaf(Leaf(field: .status, op: clause.op, value: .statusSet(Set(statuses))))
    }

    private static func resolveBoolean(_ clause: IntermediateClause) -> Resolution {
        guard clause.op == .is else { return .dropped(.offMatrix) }
        guard case .boolean(let b) = clause.value else { return .dropped(.wrongValueKind) }
        return .leaf(Leaf(field: clause.field, op: .is, value: .bool(b)))
    }

    private static func resolveTag(_ clause: IntermediateClause, context: TranslationContext) -> Resolution {
        switch clause.op {
        case .isSet, .isUnset:
            // Cardinality, not membership — both engines switch on `op`
            // before touching the value (`NSPredicateCompiler.compileTag`,
            // `SwiftEvaluator.matchTag`), so any value works. Emit the
            // conventional `.bool(true)` placeholder the "No Tags" default
            // smart filter already uses, for consistency.
            return .leaf(Leaf(field: .tag, op: clause.op, value: .bool(true)))
        case .includesAny, .includesAll, .excludesAll:
            guard case .tagNames(let names) = clause.value, !names.isEmpty else {
                return .dropped(.wrongValueKind)
            }
            let (ids, unresolved) = resolveTagIDs(names: names, context: context)
            let leaf = Leaf(field: .tag, op: clause.op, value: .uuidSet(ids))
            return unresolved.isEmpty ? .leaf(leaf) : .leafWithUnresolvedTags(leaf, unresolved)
        default:
            return .dropped(.offMatrix)
        }
    }

    /// Resolves tag names to ids case-insensitively. Names that don't match
    /// any known tag are reported (not fatal) and simply excluded from the
    /// resulting set — mirroring `CLIBridge.FilterFlags.tagIDs`, where an
    /// unknown name yields "no tasks match" rather than an error.
    private static func resolveTagIDs(names: [String], context: TranslationContext) -> (Set<UUID>, [String]) {
        var byLowerName: [String: UUID] = [:]
        for tag in context.knownTags where byLowerName[tag.name.lowercased()] == nil {
            byLowerName[tag.name.lowercased()] = tag.id
        }
        var ids: Set<UUID> = []
        var unresolved: [String] = []
        for name in names {
            if let id = byLowerName[name.lowercased()] {
                ids.insert(id)
            } else {
                unresolved.append(name)
            }
        }
        return (ids, unresolved)
    }

    private static func resolveDate(_ clause: IntermediateClause) -> Resolution {
        switch clause.op {
        case .before, .after, .on:
            switch clause.value {
            case .relativeDate(let r):
                return .leaf(Leaf(field: clause.field, op: clause.op, value: .relativeDate(r)))
            case .absoluteDateISO8601(let s):
                guard let date = parseISO8601(s) else { return .dropped(.invalidDate(s)) }
                return .leaf(Leaf(field: clause.field, op: clause.op, value: .absoluteDate(date)))
            default:
                return .dropped(.wrongValueKind)
            }
        case .withinLastDays, .withinNextDays:
            guard case .dayCount(let n) = clause.value, n >= 0 else { return .dropped(.wrongValueKind) }
            return .leaf(Leaf(field: clause.field, op: clause.op, value: .dayCount(n)))
        case .isSet, .isUnset:
            return .leaf(Leaf(field: clause.field, op: clause.op, value: .bool(true)))
        case .equalsModifiedAt:
            guard clause.field == .createdAt else { return .dropped(.offMatrix) }
            return .leaf(Leaf(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))
        default:
            return .dropped(.offMatrix)
        }
    }

    private static func resolveAttachments(_ clause: IntermediateClause) -> Resolution {
        guard clause.op == .is else { return .dropped(.offMatrix) }
        guard case .attachmentKind(let match) = clause.value else { return .dropped(.wrongValueKind) }
        return .leaf(Leaf(field: .hasAttachments, op: .is, value: .attachmentKind(match)))
    }

    /// Accepts either a full date-time or a bare `yyyy-MM-dd` ISO-8601
    /// string — day granularity is the common case for natural-language
    /// dates ("added before today").
    private static func parseISO8601(_ s: String) -> Date? {
        let dateTime = ISO8601DateFormatter()
        if let d = dateTime.date(from: s) { return d }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: s)
    }
}
