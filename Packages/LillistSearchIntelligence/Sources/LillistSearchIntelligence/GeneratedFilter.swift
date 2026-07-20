import Foundation
import LillistCore
#if canImport(FoundationModels)
import FoundationModels

/// The `@Generable` mirror of `IntermediateFilter`/`IntermediateClause` that
/// Apple's guided generation actually produces. Kept distinct from the
/// plain `LillistCore.IntermediateFilter` (which has no FoundationModels
/// dependency) for two reasons: guided generation needs plain
/// enums/structs/arrays, not `LillistCore`'s heterogeneous `IntermediateValue`
/// union; and cross-module retroactive `Generable` conformance on
/// `LillistCore` types (`Field`, `Op`, `Status`) isn't possible from here.
/// `field`/`comparator` are constrained to a closed vocabulary via
/// `GenerationGuide<String>.anyOf(...)` (built from `Field`/`Op`
/// `rawValue`s, so the constraint can't drift from the real vocabulary);
/// every other property is a best-effort optional the mapper tolerates
/// being absent or mismatched.
@available(iOS 26, macOS 26, *)
@Generable
struct GeneratedFilter {
    @Guide(description: "How the clauses combine: \"all\" for AND, \"any\" for OR")
    var combinator: String

    @Guide(description: "1 to 6 filter clauses capturing every constraint the query mentioned")
    var clauses: [GeneratedClause]
}

@available(iOS 26, macOS 26, *)
@Generable
struct GeneratedClause {
    var field: String
    var comparator: String

    @Guide(description: "Free text for contains/equals/startsWith on title, notes, or journal")
    var text: String?

    @Guide(description: "Tag names for includesAny/includesAll/excludesAll on the tag field — must be drawn from the known tag list given in the instructions, never invented")
    var tagNames: [String]?

    @Guide(description: "Status names for is/isNot on the status field: todo, started, blocked, or closed")
    var statuses: [String]?

    @Guide(description: "true/false for a boolean field (isPinned, hasChildren, hasNudges, recurrence, inTrash)")
    var boolValue: Bool?

    @Guide(description: "A relative date for before/after/on: today, tomorrow, yesterday, startOfWeek, endOfWeek, startOfMonth, endOfMonth, or a signed offset like +3d / -2w")
    var relativeDate: String?

    @Guide(description: "An explicit ISO-8601 date (yyyy-MM-dd) for before/after/on, only when the query names a specific calendar date instead of a relative one")
    var absoluteDate: String?

    @Guide(description: "A day count for withinLastDays/withinNextDays")
    var dayCount: Int?
}

@available(iOS 26, macOS 26, *)
extension GeneratedFilter {
    /// Fields a translator is allowed to propose. `ancestor` is
    /// deliberately excluded — `IntermediateFilterMapper` always drops it
    /// (no natural-language phrase maps to hierarchy scoping in v1), so
    /// offering it would only waste the model's limited vocabulary budget.
    static func offeredFields(from context: TranslationContext) -> [Field] {
        context.availableFields.filter { $0 != .ancestor }
    }

    /// Comparators a translator is allowed to propose. `isDescendantOf` /
    /// `isAncestorOf` are excluded for the same reason as `.ancestor` above.
    static let offeredComparators: [Op] = Op.allCases.filter {
        $0 != .isDescendantOf && $0 != .isAncestorOf
    }

    /// Converts the model's flat, string-typed output into the plain
    /// `IntermediateFilter` `IntermediateFilterMapper` consumes. A clause
    /// whose `field`/`comparator` strings don't parse against the real
    /// vocabulary (the guided-generation constraint should prevent this,
    /// but a model can still misfire) is dropped here rather than crashing
    /// — `IntermediateFilterMapper`'s own per-clause tolerance handles
    /// everything downstream of a successful parse.
    func toIntermediateFilter() -> IntermediateFilter {
        IntermediateFilter(
            combinator: combinator.lowercased() == "any" ? .any : .all,
            clauses: clauses.compactMap { $0.toIntermediateClause() }
        )
    }
}

@available(iOS 26, macOS 26, *)
extension GeneratedClause {
    private static let statusByName: [String: Status] = [
        "todo": .todo, "to-do": .todo, "to do": .todo,
        "started": .started, "in progress": .started,
        "blocked": .blocked,
        "closed": .closed, "done": .closed, "complete": .closed, "completed": .closed
    ]

    func toIntermediateClause() -> IntermediateClause? {
        guard let parsedField = Field(rawValue: field), let parsedOp = Op(rawValue: comparator) else {
            return nil
        }
        return IntermediateClause(field: parsedField, op: parsedOp, value: value(for: parsedOp))
    }

    /// Picks which optional carrier the given op expects. A carrier the
    /// model left empty (or filled in for the wrong op) resolves to
    /// `.none`/an empty collection — `IntermediateFilterMapper` reports
    /// that as a dropped clause rather than miscompiling it.
    private func value(for op: Op) -> IntermediateValue {
        switch op {
        case .contains, .equals, .startsWith:
            return text.map(IntermediateValue.text) ?? .none
        case .includesAny, .includesAll, .excludesAll:
            return .tagNames(tagNames ?? [])
        case .is, .isNot:
            if let statuses, !statuses.isEmpty {
                let parsed = statuses.compactMap { Self.statusByName[$0.lowercased()] }
                if !parsed.isEmpty { return .statuses(parsed) }
            }
            if let boolValue { return .boolean(boolValue) }
            return .none
        case .before, .after, .on:
            if let relativeDate, let parsed = try? RelativeDate.parse(relativeDate) {
                return .relativeDate(parsed)
            }
            if let absoluteDate { return .absoluteDateISO8601(absoluteDate) }
            return .none
        case .withinLastDays, .withinNextDays:
            return dayCount.map(IntermediateValue.dayCount) ?? .none
        case .isSet, .isUnset, .equalsModifiedAt, .isDescendantOf, .isAncestorOf:
            return .none
        }
    }
}
#endif
