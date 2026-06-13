#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

/// Visual regression baselines for the four drag-reorder states:
/// idle, dragging-between (divider), dragging-onto (border), and
/// dragging-rejected (red phantom border).
///
/// Pinned to iPhone 16 Pro logical size (393×852) per IOSScreenTourTests
/// convention. Geometry is injected synthetically into the controller so
/// the overlay renders without live layout — this is the accepted baseline
/// approach documented in the Task 14 plan.
@MainActor
final class DragReorderSnapshotTests: RecordableSnapshotTestCase {

    private let phoneSize = CGSize(width: 393, height: 852)

    // MARK: - Sample data helpers

    private func task(
        _ title: String,
        id: UUID = UUID(),
        parent: UUID? = nil
    ) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id, title: title, notes: "", status: .todo,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: parent,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_780_000_000),
            closedAt: nil, deletedAt: nil
        )
    }

    private func roots() -> [TaskNode] {
        [
            TaskNode(record: task("Buy milk"),     tagNames: [], children: []),
            TaskNode(record: task("Draft email"),  tagNames: [], children: []),
            TaskNode(record: task("Renew domain"), tagNames: [], children: []),
        ]
    }

    // MARK: - Screen factory

    private func screen(controller: DragController) -> some View {
        TasksScreen(
            roots: roots(),
            loadError: nil,
            syncIndicator: .idle(lastSync: nil),
            buildVersion: "1.0",
            sort: .constant(.personalized),
            isFilterHeaderExpanded: .constant(false),
            searchText: .constant(""),
            selectedTokens: .constant([]),
            selectedSavedFilters: .constant([]),
            isArchiveToastPresented: .constant(false),
            savedFilters: [],
            collapsedNodeIDs: [],
            archivedCount: 0,
            dragController: controller,
            onToggleCollapsed: { _ in },
            onRefresh: {},
            onStatusClick: { _ in },
            onStatusSet: { _, _ in },
            onDelete: { _ in },
            onClearFilter: {},
            onOpenSettings: {},
            onUndoArchive: {}
        )
        .frame(width: phoneSize.width, height: phoneSize.height)
    }

    // MARK: - Snapshot assertion

    private func assertDragScreen<V: View>(
        _ view: V,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let host = UIHostingController(rootView:
            view
                .environment(\.colorScheme, .light)
                .environment(\.locale, Locale(identifier: "en_US"))
        )
        host.overrideUserInterfaceStyle = .light
        host.view.frame = CGRect(origin: .zero, size: phoneSize)
        host.view.layoutIfNeeded()
        let traits = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = .light
            mutableTraits.displayScale = 2
        }
        assertSnapshot(
            of: host,
            as: .image(size: phoneSize, traits: traits),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    // MARK: - Tests

    func test_idle() {
        let controller = DragController()
        assertDragScreen(screen(controller: controller), named: "idle")
    }

    /// The drag indicator for a `.between` target renders as a tinted
    /// capsule divider between two rows. We inject synthetic geometry so
    /// the overlay renders independently of live list layout.
    func test_dragging_betweenZone() {
        let controller = DragController()
        let draggedID = UUID()
        let aboveID   = UUID()
        let belowID   = UUID()
        controller.flatRows = [
            DragReorderRow(id: draggedID, parentID: nil, depth: 0),
            DragReorderRow(id: aboveID,   parentID: nil, depth: 0),
            DragReorderRow(id: belowID,   parentID: nil, depth: 0),
        ]
        controller.geometry = [
            draggedID: CGRect(x: 12, y: 100, width: 369, height: 44),
            aboveID:   CGRect(x: 12, y: 150, width: 369, height: 44),
            belowID:   CGRect(x: 12, y: 200, width: 369, height: 44),
        ]
        // cursorY=190 is in aboveID's bottom-25% (y=[183,194)) to place
        // the phantom visually between the two rows.
        controller.beginDrag(rowID: draggedID, originalHeight: 44, cursorY: 190)
        // Target: dragged row will sit between aboveID and belowID.
        // beforeID = belowID (row dragged lands before belowID),
        // afterID  = aboveID (row dragged lands after aboveID).
        controller.setResolvedTarget(
            .between(beforeID: belowID, afterID: aboveID, parentID: nil)
        )
        assertDragScreen(screen(controller: controller), named: "dragging-between")
    }

    /// The drag indicator for an `.onto` target renders as a tinted
    /// rounded-rectangle border around the target row.
    func test_dragging_ontoZone() {
        let controller = DragController()
        let draggedID = UUID()
        let targetID  = UUID()
        controller.flatRows = [
            DragReorderRow(id: draggedID, parentID: nil, depth: 0),
            DragReorderRow(id: targetID,  parentID: nil, depth: 0),
        ]
        controller.geometry = [
            draggedID: CGRect(x: 12, y: 100, width: 369, height: 44),
            targetID:  CGRect(x: 12, y: 150, width: 369, height: 44),
        ]
        // cursorY=172 is targetID's middle-50% (y=[160,183)) — onto zone.
        controller.beginDrag(rowID: draggedID, originalHeight: 44, cursorY: 172)
        controller.setResolvedTarget(.onto(targetID: targetID))
        assertDragScreen(screen(controller: controller), named: "dragging-onto")
    }

    /// A `.rejected` target renders the phantom with a red border and
    /// no drop indicator.
    func test_dragging_rejected() {
        let controller = DragController()
        let draggedID = UUID()
        controller.flatRows = [
            DragReorderRow(id: draggedID, parentID: nil, depth: 0),
        ]
        controller.geometry = [
            draggedID: CGRect(x: 12, y: 100, width: 369, height: 44),
        ]
        controller.beginDrag(rowID: draggedID, originalHeight: 44, cursorY: 122)
        controller.setResolvedTarget(.rejected)
        assertDragScreen(screen(controller: controller), named: "dragging-rejected")
    }
}
#endif
