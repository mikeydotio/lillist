import Testing
import Foundation
import CoreData
@testable import LillistCore

/// C2, M2, H4 — the restore half of the trash/restore state machine.
/// **Product decision (Mikey, 2026-07-28):** restoring a child whose parent
/// is still trashed promotes the child to root (C2). Restore must also
/// clear `archivedAt`, not just `deletedAt` (M2), and must land the
/// restored task at a fresh, non-colliding position among its (possibly
/// new) live siblings rather than keep its stale pre-trash position (H4).
@Suite("C2/M2/H4 restore state machine")
struct TaskStoreRestoreStateMachineTests {
    @Test("C2: restoring a child whose parent stays trashed promotes it to root")
    func restoreChildOfStillTrashedParentPromotesToRoot() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.softDelete(id: parentID) // cascades to trash child too

        try await store.restore(id: childID) // parentID stays trashed

        let child = try await store.fetch(id: childID)
        #expect(child.deletedAt == nil)
        #expect(child.parentID == nil, "a child restored under a still-trashed parent must be promoted to root")
        let roots = try await store.children(of: nil)
        #expect(roots.contains { $0.id == childID }, "the promoted child must be visible at the top level")
    }

    @Test("C2: restoring the parent itself (not a child) restores normally without promotion")
    func restoreOfLiveParentDoesNotPromote() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let grandparentID = try await store.create(title: "grandparent")
        let parentID = try await store.create(title: "parent", parent: grandparentID)
        try await store.softDelete(id: parentID)

        try await store.restore(id: parentID)

        let parent = try await store.fetch(id: parentID)
        #expect(parent.deletedAt == nil)
        #expect(parent.parentID == grandparentID, "restoring under a LIVE parent must not promote to root")
    }

    @Test("M2: restore clears archivedAt so the task is fully visible again")
    func restoreClearsArchivedAt() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.archive(ids: [id])
        try await store.softDelete(id: id)

        try await store.restore(id: id)

        let record = try await store.fetch(id: id)
        #expect(record.deletedAt == nil)
        #expect(record.archivedAt == nil)
    }

    @Test("M2: cascade restore clears archivedAt on descendants too")
    func restoreCascadeClearsArchivedAtOnDescendants() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.archive(ids: [childID])
        try await store.softDelete(id: parentID)

        try await store.restore(id: parentID)

        let child = try await store.fetch(id: childID)
        #expect(child.deletedAt == nil)
        #expect(child.archivedAt == nil)
    }

    @Test("H4: nextPositionDetail ignores trashed siblings when computing the bottom edge")
    func nextPositionIgnoresTrashedSiblings() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "a")
        let b = try await store.create(title: "b")
        try await store.softDelete(id: b)

        let c = try await store.create(title: "c")

        let aRecord = try await store.fetch(id: a)
        let cRecord = try await store.fetch(id: c)
        #expect(
            cRecord.position == aRecord.position + 1.0,
            "the new task must be placed relative to the live edge (a), ignoring the trashed b"
        )
    }

    @Test("H4: restore lands at a non-colliding position even if a live sibling occupies its old slot")
    func restoreAvoidsPositionCollision() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "a")
        let b = try await store.create(title: "b")
        _ = try await store.create(title: "c")
        try await store.softDelete(id: b) // b's position stays at its old value, now trashed

        // Simulate a recompaction that assigned a live sibling to b's exact
        // old slot while b sat in the trash — H4's precise failure scenario
        // (today, restore keeps b's stale position with no reassignment).
        let ctx = p.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", a as CVarArg)
            let aRow = try ctx.fetch(req).first!
            let bReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            bReq.predicate = NSPredicate(format: "id == %@", b as CVarArg)
            let bRow = try ctx.fetch(bReq).first!
            aRow.position = bRow.position // collision, once b is restored unchanged
            try ctx.save()
        }

        try await store.restore(id: b)

        let siblings = try await store.children(of: nil)
        let positions = siblings.map(\.position)
        #expect(Set(positions).count == positions.count, "no two live siblings may share a position after restore")
        let bRecord = try await store.fetch(id: b)
        #expect(bRecord.deletedAt == nil)
    }
}
