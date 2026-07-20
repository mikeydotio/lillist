import Foundation

/// A single field/operator/value clause in a translator's flat output.
/// Mirrors `Leaf` in shape, but carries an `IntermediateValue` instead of a
/// `Value` — see that type's doc comment for why. `IntermediateFilterMapper`
/// validates and converts this into a real `Leaf`.
public struct IntermediateClause: Sendable, Equatable {
    public var field: Field
    public var op: Op
    public var value: IntermediateValue

    public init(field: Field, op: Op, value: IntermediateValue) {
        self.field = field
        self.op = op
        self.value = value
    }
}

/// The flat schema a `FilterQueryTranslator` emits from natural-language
/// text. Deliberately single-combinator (no nested groups) in v1 — it
/// covers both of issue #51's examples ("added before today"; "has due date
/// in the past and is incomplete") — even though the target `PredicateGroup`
/// already supports arbitrary nesting; a one-deep nested-group extension is
/// an additive follow-up if mixed AND/OR phrasing is needed later.
public struct IntermediateFilter: Sendable, Equatable {
    public var combinator: PredicateGroup.Combinator
    public var clauses: [IntermediateClause]

    public init(combinator: PredicateGroup.Combinator, clauses: [IntermediateClause]) {
        self.combinator = combinator
        self.clauses = clauses
    }
}
