import Testing
import Foundation
@testable import LillistCore

/// `LIL-95`: ``WidgetRowPlan`` is the shared truncation logic used both by
/// ``WidgetSnapshotBuilder`` (capping the persisted snapshot at `rowCap`) and
/// by the widget card view (capping further at a family's `maxRows`). One
/// implementation so the two cap points can't drift apart on the
/// stranded-context-row rule.
@Suite("WidgetRowPlan")
struct WidgetRowPlanTests {
    private func row(
        _ title: String,
        parentID: UUID? = nil,
        depth: Int = 0,
        isContext: Bool = false,
        id: UUID = UUID()
    ) -> WidgetSnapshot.Row {
        .init(id: id, title: title, status: .todo, parentID: parentID, depth: depth, isContext: isContext)
    }

    @Test("with room to spare, every row passes through unchanged")
    func passesThroughWhenUnderLimit() {
        let a = row("A")
        let b = row("B", parentID: a.id, depth: 1)
        let plan = WidgetRowPlan.plan(rows: [a, b], limit: 10)

        #expect(plan.map(\.row.title) == ["A", "B"])
        #expect(plan.map(\.depth) == [0, 1])
        #expect(plan.map(\.showsParentMarker) == [false, false])
    }

    @Test("a truncation that strands a context row with none of its children strips it")
    func truncationStripsStrandedContextRow() {
        let context = row("Ship v0.21", isContext: true)
        let child = row("Write release notes", parentID: context.id, depth: 1)
        let other = row("Buy milk")
        // Cap right after the context row — its only child never makes it in.
        let plan = WidgetRowPlan.plan(rows: [context, child, other], limit: 1)

        #expect(plan.map(\.row.title) == [], "a lone context row with no surviving children is meaningless")
    }

    @Test("truncation keeps a context row whose child still fits")
    func truncationKeepsContextRowWithSurvivingChild() {
        let context = row("Ship v0.21", isContext: true)
        let child = row("Write release notes", parentID: context.id, depth: 1)
        let other = row("Buy milk")
        let plan = WidgetRowPlan.plan(rows: [context, child, other], limit: 2)

        #expect(plan.map(\.row.title) == ["Ship v0.21", "Write release notes"])
    }

    @Test("marker is false when the parent survives truncation, true when it doesn't")
    func markerReflectsFinalVisibility() {
        let parent = row("Ship v0.21")
        let child = row("Write release notes", parentID: parent.id, depth: 1)
        let full = WidgetRowPlan.plan(rows: [parent, child], limit: 10)
        #expect(full.map(\.showsParentMarker) == [false, false])

        // Cap before the parent — the child, if it survived alone, would need
        // the marker. (Parent-before-child DFS means this specific shape
        // can't arise from `shapeRows` output, but the marker rule itself
        // must still hold generically against whatever survives the cap.)
        let childOnly = WidgetRowPlan.plan(rows: [child], limit: 10)
        #expect(childOnly.map(\.showsParentMarker) == [true])
    }

    @Test("an empty row list plans to an empty result")
    func emptyInput() {
        #expect(WidgetRowPlan.plan(rows: [], limit: 10).isEmpty)
    }

    @Test("a limit of zero plans to an empty result")
    func zeroLimit() {
        let a = row("A")
        #expect(WidgetRowPlan.plan(rows: [a], limit: 0).isEmpty)
    }
}
