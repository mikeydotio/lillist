// Cross-platform: FlatTaskRow/TreeFlattener are shared by the iOS app and
// the macOS main window (see FlatTaskRow.swift's own header comment), so
// unlike TaskTreeTests.swift this suite is NOT `#if os(iOS)`-gated — it
// exercises pure Foundation types and runs on both platforms' test passes.
import Testing
import Foundation
import LillistCore
@testable import LillistUI

/// LIL-97 — `FlatTaskRow.isOrphan` is the app-side twin of the widget's
/// `showsParentMarker`: true for a row `TaskTree.build` promoted to top
/// level because its true parent (`node.record.parentID`) isn't in the
/// current result set, distinguishing it from a genuine root.
@Suite("FlatTaskRow.isOrphan")
struct FlatTaskRowTests {

    // MARK: - Fixtures

    private func record(
        _ title: String,
        id: UUID,
        parent: UUID? = nil
    ) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id,
            title: title,
            notes: "",
            status: .todo,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: 0,
            isPinned: false,
            parentID: parent,
            createdAt: nil,
            modifiedAt: nil,
            closedAt: nil,
            deletedAt: nil
        )
    }

    @Test("A genuine root (parentID nil) is not an orphan")
    func genuineRootIsNotOrphan() {
        let id = UUID()
        let roots = TaskTree.build(records: [record("A", id: id)], tagsByTask: [:], sort: .personalized)
        let flat = TreeFlattener.flatten(roots)
        #expect(flat.first?.isOrphan == false)
    }

    @Test("A child nested under its visible parent is not an orphan")
    func nestedChildIsNotOrphan() {
        let parentID = UUID()
        let childID = UUID()
        let records = [
            record("Parent", id: parentID),
            record("Child", id: childID, parent: parentID)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        let flat = TreeFlattener.flatten(roots)
        let child = flat.first { $0.node.record.id == childID }
        #expect(child?.isOrphan == false)
        #expect(child?.depth == 1)
    }

    @Test("A subtask promoted to root because its parent is absent IS an orphan")
    func promotedOrphanIsOrphan() {
        let ghostParentID = UUID()
        let orphanID = UUID()
        let records = [record("Orphan", id: orphanID, parent: ghostParentID)]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        let flat = TreeFlattener.flatten(roots)
        let orphan = flat.first { $0.node.record.id == orphanID }
        #expect(orphan?.isOrphan == true)
        #expect(orphan?.depth == 0, "an orphan is promoted to depth 0, indistinguishable from a real root by depth alone")
    }

    @Test("A promoted orphan's OWN visible children are not themselves orphans")
    func orphanChildrenAreNotOrphans() {
        let ghostParentID = UUID()
        let orphanID = UUID()
        let grandchildID = UUID()
        let records = [
            record("Orphan", id: orphanID, parent: ghostParentID),
            record("Grandchild", id: grandchildID, parent: orphanID)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        let flat = TreeFlattener.flatten(roots)
        let orphan = flat.first { $0.node.record.id == orphanID }
        let grandchild = flat.first { $0.node.record.id == grandchildID }
        #expect(orphan?.isOrphan == true)
        #expect(grandchild?.isOrphan == false, "the orphan IS the grandchild's visible parent, so the grandchild nests normally")
        #expect(grandchild?.depth == 1)
    }

    @Test("A collapsed orphan (children hidden) is still detected as an orphan")
    func collapsedOrphanStillDetected() {
        let ghostParentID = UUID()
        let orphanID = UUID()
        let childID = UUID()
        let records = [
            record("Orphan", id: orphanID, parent: ghostParentID),
            record("Child", id: childID, parent: orphanID)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        let flat = TreeFlattener.flatten(roots, collapsed: [orphanID])
        #expect(flat.map(\.node.record.id) == [orphanID], "collapsing hides the child row, but the orphan row itself must still be present and flagged")
        #expect(flat.first?.isOrphan == true)
    }
}
