import XCTest
@testable import LillistUI

/// Unit coverage for the pure `DragTarget` → store-mutation mapping shared
/// by macOS `TaskListView.applyDrop` and iOS `TasksView.applyDrop`. The
/// previous macOS `DragDropInteractionTests` re-implemented this mapping
/// and silently mis-mapped `.onto` to an unconditional reparent, never
/// exercising the "drop as first child when the target has visible
/// children" branch the apps actually perform.
final class DragDropResolverTests: XCTestCase {

    // The `.between` target routes straight to a `reorder`; the dragged ID is
    // supplied by the dispatching app at dispatch time, not by the resolver,
    // so `DragMutation.reorder` carries only `after`/`before`.
    func test_between_mapsToReorderWithBeforeAndAfter() {
        let before = UUID()
        let after = UUID()
        let mutation = DragDropResolver.resolve(
            target: .between(beforeID: before, afterID: after, parentID: nil),
            flatRows: []
        )
        XCTAssertEqual(mutation, .reorder(after: after, before: before))
    }

    func test_ontoTargetWithVisibleChild_mapsToReorderBeforeFirstChild() {
        let parent = UUID()
        let firstChild = UUID()
        let secondChild = UUID()
        let flatRows = [
            DragReorderRow(id: parent, parentID: nil, depth: 0),
            DragReorderRow(id: firstChild, parentID: parent, depth: 1),
            DragReorderRow(id: secondChild, parentID: parent, depth: 1),
        ]
        let mutation = DragDropResolver.resolve(
            target: .onto(targetID: parent),
            flatRows: flatRows
        )
        XCTAssertEqual(mutation, .reorder(after: nil, before: firstChild))
    }

    func test_ontoCollapsedOrLeafTarget_mapsToReparentAppend() {
        let parent = UUID()
        // No row whose parentID == parent → target is collapsed or a leaf.
        let flatRows = [
            DragReorderRow(id: parent, parentID: nil, depth: 0),
            DragReorderRow(id: UUID(), parentID: nil, depth: 0),
        ]
        let mutation = DragDropResolver.resolve(
            target: .onto(targetID: parent),
            flatRows: flatRows
        )
        XCTAssertEqual(mutation, .reparent(newParent: parent))
    }

    func test_rejectedTarget_mapsToNoop() {
        XCTAssertEqual(
            DragDropResolver.resolve(target: .rejected, flatRows: []),
            .noop
        )
    }

    func test_noneTarget_mapsToNoop() {
        XCTAssertEqual(
            DragDropResolver.resolve(target: .none, flatRows: []),
            .noop
        )
    }
}
