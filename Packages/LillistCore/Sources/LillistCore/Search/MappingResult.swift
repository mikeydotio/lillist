import Foundation

/// Why `IntermediateFilterMapper` couldn't turn a clause into a `Leaf`.
public enum DropReason: Sendable, Equatable {
    /// The (field, op) pair is not legal per the rule engine's Field × Op ×
    /// Value matrix (`NSPredicateCompiler` / `SwiftEvaluator`) — e.g.
    /// `journalText equals`, or a boolean field paired with anything but `is`.
    case offMatrix
    /// The (field, op) pair IS legal, but the clause's `IntermediateValue`
    /// case doesn't carry the shape that op requires (e.g. `status is` with
    /// a `.text` payload instead of `.statuses`), or carries an
    /// out-of-range value (e.g. a negative day count).
    case wrongValueKind
    /// A date field's `absoluteDateISO8601` string didn't parse.
    case invalidDate(String)
}

/// A clause `IntermediateFilterMapper` could not represent as a `Leaf`,
/// together with why. Surfaced to the UI/CLI as "couldn't understand: …"
/// rather than silently vanishing.
public struct DroppedClause: Sendable, Equatable {
    public var field: Field
    public var op: Op
    public var reason: DropReason

    public init(field: Field, op: Op, reason: DropReason) {
        self.field = field
        self.op = op
        self.reason = reason
    }
}

/// The result of mapping an `IntermediateFilter` to a `PredicateGroup`.
/// Mapping never throws — a clause the mapper can't place is reported in
/// `dropped` (per-clause tolerance) rather than failing the whole query, so
/// "added before today and is urgent" still yields the date predicate.
public struct MappingResult: Sendable, Equatable {
    public var group: PredicateGroup
    public var dropped: [DroppedClause]
    /// Tag names a `tag` clause mentioned that didn't match any
    /// `TranslationContext.knownTags` entry. The clause is still emitted
    /// (with whatever names DID resolve — possibly none, which compiles to
    /// "matches nothing"), mirroring `CLIBridge.FilterFlags` tag-name
    /// semantics; this list is purely informational, for UX transparency.
    public var unresolvedTagNames: [String]

    public init(
        group: PredicateGroup,
        dropped: [DroppedClause] = [],
        unresolvedTagNames: [String] = []
    ) {
        self.group = group
        self.dropped = dropped
        self.unresolvedTagNames = unresolvedTagNames
    }

    /// True when every proposed clause was dropped (or none were proposed)
    /// — the signal to tell the user "I couldn't understand that" instead of
    /// silently running a filter with no predicates (which matches
    /// everything non-trashed, per `NSPredicateCompiler`'s empty-group rule).
    public var isEmpty: Bool {
        group.predicates.isEmpty
    }
}
