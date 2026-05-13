import Foundation

/// A combinator over zero-or-more child predicates. Per design Section 5,
/// v1's authoring UI is flat AND/OR; the data model is already recursive to
/// accommodate v2's nested groups.
public struct PredicateGroup: Codable, Sendable, Equatable {
    public enum Combinator: String, Codable, Sendable { case all, any }

    public var combinator: Combinator
    public var predicates: [Predicate]

    public init(combinator: Combinator, predicates: [Predicate]) {
        self.combinator = combinator
        self.predicates = predicates
    }
}
