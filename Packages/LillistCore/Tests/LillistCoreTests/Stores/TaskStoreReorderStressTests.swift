import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Stress-tests the heal-then-recheck path in `TaskStore.reorder` by
/// repeating the two-context position-tie scenario 25 times. Each
/// iteration uses a fresh in-memory store, so there is no shared state
/// between iterations. The suite is `.serialized` to avoid Core Data
/// SIGSEGV under high in-memory-store concurrency (see engineering-notes
/// 2026-06-04 entry).
@Suite("TaskStore reorder heal — stress", .serialized)
struct TaskStoreReorderStressTests {
    private static let iterations = 25

    @Test("Two-context tie heals under repeated execution (T19)")
    func twoContextTieHealsRepeatedly() async throws {
        for iteration in 0..<Self.iterations {
            let p = try await TestStore.make()
            let store = TaskStore(persistence: p)

            // Create parent and first child A (position = 1.0)
            let parentID = try await store.create(title: "P")
            let aID = try await store.create(title: "A", parent: parentID)

            // Both contexts observe the current max (1.0) and compute
            // nextPosition = 2.0 independently — the classic tie scenario.
            let ctxA = p.container.viewContext
            let ctxB = p.container.newBackgroundContext()
            ctxB.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

            let xID = UUID()
            let yID = UUID()

            // ctxA inserts X at position 2.0
            try await ctxA.perform {
                let parentReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                parentReq.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
                parentReq.fetchLimit = 1
                let parentObj = try ctxA.fetch(parentReq).first

                let x = LillistTask(context: ctxA)
                x.id = xID
                x.title = "X"
                x.status = .todo
                x.position = 2.0
                x.startHasTime = false
                x.deadlineHasTime = false
                x.isPinned = false
                x.createdAt = Date()
                x.modifiedAt = x.createdAt
                x.parent = parentObj
                try ctxA.save()
            }

            // ctxB inserts Y at position 2.0 (still on its stale snapshot)
            try await ctxB.perform {
                let parentReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                parentReq.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
                parentReq.fetchLimit = 1
                let parentObj = try ctxB.fetch(parentReq).first

                let y = LillistTask(context: ctxB)
                y.id = yID
                y.title = "Y"
                y.status = .todo
                y.position = 2.0
                y.startHasTime = false
                y.deadlineHasTime = false
                y.isPinned = false
                y.createdAt = Date()
                y.modifiedAt = y.createdAt
                y.parent = parentObj
                try ctxB.save()
            }

            // Merge ctxB into viewContext
            await ctxA.perform { ctxA.refreshAllObjects() }

            // Reorder A into the gap between X and Y (tied at 2.0)
            // This is the operation that used to brick with "anchors out of order"
            try await store.reorder(id: aID, after: xID, before: yID)

            // Verify: all three siblings have strictly increasing positions
            let children = try await store.children(of: parentID)
            #expect(children.count == 3,
                    "iteration \(iteration): expected 3 children, got \(children.count)")
            let positions = children.map(\.position)
            for i in 1..<positions.count {
                #expect(positions[i] > positions[i-1],
                        "iteration \(iteration): positions not strictly increasing: \(positions)")
            }
            #expect(Set(positions).count == positions.count,
                    "iteration \(iteration): duplicate positions found: \(positions)")
        }
    }
}
