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

@Suite("SwiftEvaluator — date slice")
struct SwiftEvaluatorDateTests {
    static let now = Date(timeIntervalSince1970: 1_715_500_000)
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func snap(deadline: Date? = nil, start: Date? = nil, created: Date = now, modified: Date = now, closed: Date? = nil) -> SwiftEvaluator.TaskSnapshot {
        SwiftEvaluator.TaskSnapshot(
            id: UUID(), title: "t", notes: "",
            status: .todo,
            start: start, startHasTime: false,
            deadline: deadline, deadlineHasTime: false,
            createdAt: created, modifiedAt: modified, closedAt: closed,
            isPinned: false, inTrash: false,
            hasChildren: false, childCount: 0,
            tagIDs: [], ancestorIDs: [],
            journalNoteBodies: [], attachmentKinds: [],
            hasNudges: false, isRecurring: false
        )
    }

    @Test("deadline before absoluteDate")
    func before() {
        let cutoff = SwiftEvaluatorDateTests.now.addingTimeInterval(60)
        let before = SwiftEvaluatorDateTests.now.addingTimeInterval(-60)
        let after = SwiftEvaluatorDateTests.now.addingTimeInterval(120)
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .before, value: .absoluteDate(cutoff)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: before), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: after), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == false)
    }

    @Test("deadline withinNextDays(7)")
    func withinNext() {
        let inThree = SwiftEvaluatorDateTests.cal.date(byAdding: .day, value: 3, to: SwiftEvaluatorDateTests.now)!
        let inTen = SwiftEvaluatorDateTests.cal.date(byAdding: .day, value: 10, to: SwiftEvaluatorDateTests.now)!
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(7)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: inThree), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: inTen), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == false)
    }

    @Test("deadline isSet vs isUnset")
    func isSet() {
        let setG = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
        ])
        let unsetG = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: setG, against: snap(deadline: Date())) == true)
        #expect(SwiftEvaluator.evaluate(group: setG, against: snap(deadline: nil)) == false)
        #expect(SwiftEvaluator.evaluate(group: unsetG, against: snap(deadline: nil)) == true)
    }

    @Test("createdAt equalsModifiedAt")
    func createdEqualsModified() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(created: t, modified: t)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(created: t, modified: t.addingTimeInterval(1))) == false)
    }

    @Test("start withinNextDays resolves relative to provided now")
    func relativeToNow() {
        let t = SwiftEvaluatorDateTests.cal.date(byAdding: .day, value: 2, to: SwiftEvaluatorDateTests.now)!
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .start, op: .withinNextDays, value: .dayCount(5)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(start: t), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == true)
    }
}
