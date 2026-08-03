import Testing
import Foundation
@testable import LillistCore

/// `LIL-95`: ``WidgetRowPlan`` is the shared truncation/re-leveling logic used
/// both by ``WidgetSnapshotBuilder`` (capping the persisted snapshot at
/// `rowCap`) and by the widget card view (capping further at a family's
/// `maxRows`). One implementation so the two cap points can't drift apart on
/// the stranded-context-row and re-leveling rules.
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
        let plan = WidgetRowPlan.plan(rows: [a, b], limit: 10, allowsContextRows: true)

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
        let plan = WidgetRowPlan.plan(rows: [context, child, other], limit: 1, allowsContextRows: true)

        #expect(plan.map(\.row.title) == [], "a lone context row with no surviving children is meaningless")
    }

    @Test("truncation keeps a context row whose child still fits")
    func truncationKeepsContextRowWithSurvivingChild() {
        let context = row("Ship v0.21", isContext: true)
        let child = row("Write release notes", parentID: context.id, depth: 1)
        let other = row("Buy milk")
        let plan = WidgetRowPlan.plan(rows: [context, child, other], limit: 2, allowsContextRows: true)

        #expect(plan.map(\.row.title) == ["Ship v0.21", "Write release notes"])
    }

    @Test("allowsContextRows: false drops every context row")
    func dropsContextRowsWhenDisallowed() {
        let context = row("Ship v0.21", isContext: true)
        let child = row("Write release notes", parentID: context.id, depth: 1)
        let plan = WidgetRowPlan.plan(rows: [context, child], limit: 10, allowsContextRows: false)

        #expect(plan.map(\.row.isContext) == [false])
        #expect(plan.map(\.row.title) == ["Write release notes"])
    }

    @Test("a member orphaned by a dropped context row flattens to root and gets the marker")
    func orphanedByDroppedContextRowFlattensAndMarks() {
        let context = row("Ship v0.21", isContext: true)
        let child = row("Write release notes", parentID: context.id, depth: 1)
        let plan = WidgetRowPlan.plan(rows: [context, child], limit: 10, allowsContextRows: false)

        let item = try! #require(plan.first)
        #expect(item.depth == 0, "no context row to nest under, so it flattens to root")
        #expect(item.showsParentMarker == true, "its true parent isn't shown, so the triangle must appear")
    }

    @Test("a member whose parent IS a visible member keeps its nesting when context rows are disallowed")
    func nestingUnderAVisibleMemberSurvivesWhenContextRowsDisallowed() {
        let parent = row("Ship v0.21") // a real, matching member — not a context row
        let child = row("Write release notes", parentID: parent.id, depth: 1)
        let plan = WidgetRowPlan.plan(rows: [parent, child], limit: 10, allowsContextRows: false)

        #expect(plan.map(\.row.title) == ["Ship v0.21", "Write release notes"])
        #expect(plan.map(\.depth) == [0, 1])
        #expect(plan.map(\.showsParentMarker) == [false, false])
    }

    @Test("re-leveling through a dropped context row clamps to 2 same as normal depth")
    func reLevelingRespectsTheDepthClamp() {
        // parent(member, depth0) -> context(dropped) -> child(member) -> grandchild(member)
        // With the context row gone, `child` flattens to root (depth 0) and
        // `grandchild` nests one level under it (depth 1) — it does NOT
        // retain its original depth-2 tier, because its immediate parent
        // (the context row) is gone, not merely re-leveled.
        let context = row("Ship v0.21", isContext: true)
        let child = row("Write release notes", parentID: context.id, depth: 1)
        let grandchild = row("Proofread", parentID: child.id, depth: 2)
        let plan = WidgetRowPlan.plan(rows: [context, child, grandchild], limit: 10, allowsContextRows: false)

        #expect(plan.map(\.row.title) == ["Write release notes", "Proofread"])
        #expect(plan.map(\.depth) == [0, 1])
        #expect(plan[0].showsParentMarker == true)
        #expect(plan[1].showsParentMarker == false)
    }

    @Test("marker is false when the parent survives truncation, true when it doesn't")
    func markerReflectsFinalVisibility() {
        let parent = row("Ship v0.21")
        let child = row("Write release notes", parentID: parent.id, depth: 1)
        let full = WidgetRowPlan.plan(rows: [parent, child], limit: 10, allowsContextRows: true)
        #expect(full.map(\.showsParentMarker) == [false, false])

        // Cap before the parent — the child, if it survived alone, would need
        // the marker. (Parent-before-child DFS means this specific shape
        // can't arise from `shapeRows` output, but the marker rule itself
        // must still hold generically against whatever survives the cap.)
        let childOnly = WidgetRowPlan.plan(rows: [child], limit: 10, allowsContextRows: true)
        #expect(childOnly.map(\.showsParentMarker) == [true])
    }

    @Test("an empty row list plans to an empty result")
    func emptyInput() {
        #expect(WidgetRowPlan.plan(rows: [], limit: 10, allowsContextRows: true).isEmpty)
    }

    @Test("a limit of zero plans to an empty result")
    func zeroLimit() {
        let a = row("A")
        #expect(WidgetRowPlan.plan(rows: [a], limit: 0, allowsContextRows: true).isEmpty)
    }
}
