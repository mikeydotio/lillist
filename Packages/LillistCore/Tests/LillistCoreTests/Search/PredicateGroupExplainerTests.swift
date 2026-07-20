import Testing
import Foundation
@testable import LillistCore

@Suite("PredicateGroupExplainer")
struct PredicateGroupExplainerTests {
    @Test("an empty group has no explanation")
    func emptyGroup() {
        #expect(PredicateGroupExplainer.explain(PredicateGroup(combinator: .all, predicates: [])) == nil)
    }

    @Test("a single leaf renders its plain-English shape")
    func singleLeaf() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(Leaf(field: .createdAt, op: .before, value: .relativeDate(.today)))
        ])
        #expect(PredicateGroupExplainer.explain(group) == "created before today")
    }

    @Test("an .all group joins clauses with 'and'")
    func allJoinsWithAnd() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(Leaf(field: .deadline, op: .before, value: .relativeDate(.today))),
            .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
        ])
        #expect(PredicateGroupExplainer.explain(group) == "deadline before today and status is not closed")
    }

    @Test("an .any group joins clauses with 'or'")
    func anyJoinsWithOr() {
        let group = PredicateGroup(combinator: .any, predicates: [
            .leaf(Leaf(field: .isPinned, op: .is, value: .bool(true))),
            .leaf(Leaf(field: .tag, op: .isUnset, value: .bool(true)))
        ])
        #expect(PredicateGroupExplainer.explain(group) == "pinned or has no tags")
    }

    @Test("a nested group renders parenthesized")
    func nestedGroup() {
        let inner = PredicateGroup(combinator: .any, predicates: [
            .leaf(Leaf(field: .deadline, op: .on, value: .relativeDate(.today))),
            .leaf(Leaf(field: .start, op: .on, value: .relativeDate(.today)))
        ])
        let outer = PredicateGroup(combinator: .all, predicates: [
            .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed]))),
            .group(inner)
        ])
        #expect(PredicateGroupExplainer.explain(outer) == "status is not closed and (deadline on today or start on today)")
    }

    @Test("an unrecognized leaf shape is silently omitted, not guessed at")
    func unrecognizedLeafOmitted() {
        // isAncestorOf's engine-level stub has no natural rendering.
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(Leaf(field: .ancestor, op: .isAncestorOf, value: .uuidSet([])))
        ])
        #expect(PredicateGroupExplainer.explain(group) == nil)
    }
}
