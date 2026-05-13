import Testing
import Foundation
@testable import LillistCore

@Suite("SwiftEvaluator — scalar/string slice")
struct SwiftEvaluatorTests {
    private func snapshot(
        title: String = "T",
        notes: String = "",
        status: Status = .todo,
        isPinned: Bool = false,
        inTrash: Bool = false,
        hasChildren: Bool = false
    ) -> SwiftEvaluator.TaskSnapshot {
        SwiftEvaluator.TaskSnapshot(
            id: UUID(),
            title: title,
            notes: notes,
            status: status,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            createdAt: Date(), modifiedAt: Date(),
            closedAt: nil,
            isPinned: isPinned,
            inTrash: inTrash,
            hasChildren: hasChildren,
            childCount: hasChildren ? 1 : 0,
            tagIDs: [],
            ancestorIDs: [],
            journalNoteBodies: [],
            attachmentKinds: [],
            hasNudges: false,
            isRecurring: false
        )
    }

    @Test("Empty group matches non-trashed snapshot")
    func emptyGroup() {
        let g = PredicateGroup(combinator: .all, predicates: [])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot()) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(inTrash: true)) == false)
    }

    @Test("title contains")
    func titleContains() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "Design review")) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "Spec writing")) == false)
    }

    @Test("title equals is case-insensitive")
    func titleEqualsCaseInsensitive() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .equals, value: .string("Inbox")))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "inbox")) == true)
    }

    @Test("status is statusSet")
    func statusIs() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo, .started])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(status: .todo)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(status: .closed)) == false)
    }

    @Test("isPinned is bool")
    func isPinned() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(isPinned: true)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(isPinned: false)) == false)
    }

    @Test("hasChildren is bool")
    func hasChildren() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasChildren, op: .is, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(hasChildren: true)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(hasChildren: false)) == false)
    }

    @Test("Explicit inTrash leaf suppresses implicit trash filter")
    func explicitInTrash() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .inTrash, op: .is, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(inTrash: true)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(inTrash: false)) == false)
    }

    @Test("Combinator .any matches at least one leaf")
    func anyCombinator() {
        let g = PredicateGroup(combinator: .any, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("zzz"))),
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(status: .todo)) == true)
    }
}
