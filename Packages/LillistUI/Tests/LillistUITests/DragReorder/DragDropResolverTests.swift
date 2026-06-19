import XCTest
@testable import LillistUI

/// Unit coverage for the pure `DragTarget` → store-mutation mapping shared
/// by macOS `TaskListView.applyDrop` and iOS `TasksView.applyDrop`.
final class DragDropResolverTests: XCTestCase {

    // A `.between` with anchors routes to a `reorder` carrying the authoritative
    // target parent (so a de-parent is honored, not re-inferred). The dragged ID
    // is supplied by the dispatching app, not the resolver.
    func test_between_mapsToReorderWithParentAndAnchors() {
        let before = UUID()
        let after = UUID()
        let parent = UUID()
        let mutation = DragDropResolver.resolve(
            target: .between(beforeID: before, afterID: after, parentID: parent)
        )
        XCTAssertEqual(mutation, .reorder(parent: parent, after: after, before: before))
    }

    // A de-parent to top level carries parentID == nil through to the reorder.
    func test_between_topLevel_mapsToReorderWithNilParent() {
        let after = UUID()
        let mutation = DragDropResolver.resolve(
            target: .between(beforeID: nil, afterID: after, parentID: nil)
        )
        XCTAssertEqual(mutation, .reorder(parent: nil, after: after, before: nil))
    }

    // No sibling anchors (first/only child of a childless or collapsed parent) →
    // reparent-append, since there is no sibling to position against.
    func test_between_noAnchors_mapsToReparent() {
        let parent = UUID()
        let mutation = DragDropResolver.resolve(
            target: .between(beforeID: nil, afterID: nil, parentID: parent)
        )
        XCTAssertEqual(mutation, .reparent(newParent: parent))
    }

    func test_rejectedTarget_mapsToNoop() {
        XCTAssertEqual(DragDropResolver.resolve(target: .rejected), .noop)
    }

    func test_noneTarget_mapsToNoop() {
        XCTAssertEqual(DragDropResolver.resolve(target: .none), .noop)
    }
}
