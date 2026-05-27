import XCTest
import LillistCore
import LillistUI

@MainActor
final class DragDropInteractionTests: XCTestCase {
    func test_dropOnto_callsReparent() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")

        let controller = DragController(onDrop: { _, _ in })
        await applyTarget(.onto(targetID: a), draggedID: b, store: store, controller: controller)

        let kidsOfA = try await store.children(of: a).map(\.id)
        XCTAssertEqual(kidsOfA, [b])
    }

    func test_dropBetween_callsReorder() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        let c = try await store.create(title: "C")
        // Move C before A → order [C, A, B]
        let controller = DragController(onDrop: { _, _ in })
        await applyTarget(
            .between(beforeID: a, afterID: nil, parentID: nil),
            draggedID: c,
            store: store,
            controller: controller
        )

        let order = try await store.children(of: nil).map(\.id)
        XCTAssertEqual(order, [c, a, b])
    }

    func test_dropOntoSelf_isRejectedByController() {
        let id = UUID()
        let controller = DragController(onDrop: { _, _ in })
        controller.flatRows = [DragReorderRow(id: id, parentID: nil, depth: 0)]
        controller.geometry = [id: CGRect(x: 0, y: 0, width: 100, height: 44)]
        controller.beginDrag(rowID: id, originalHeight: 44, cursorY: 22)
        let t = controller.resolveTarget(forDraggedID: id, atY: 22)
        XCTAssertEqual(t, .rejected)
    }

    // MARK: - Helpers

    /// Bridge a `DragTarget` to the store calls the macOS container makes.
    private func applyTarget(
        _ target: DragTarget,
        draggedID: UUID,
        store: TaskStore,
        controller: DragController
    ) async {
        switch target {
        case .between(let beforeID, let afterID, _):
            try? await store.reorder(id: draggedID, after: afterID, before: beforeID)
        case .onto(let parentID):
            try? await store.reparent(id: draggedID, newParent: parentID)
        case .rejected, .none:
            break
        }
    }
}
