import Testing
import Foundation
@testable import LillistCore

/// L3: `syncCounts()` used to run entirely inside a `context.perform` block
/// on the main-queue `viewContext`, materializing every task's
/// `NSManagedObjectID` there. It now runs on a dedicated background
/// context. This is directly observable via timing: occupying the
/// `viewContext` with a bounded-duration blocking operation must not add
/// that duration to `syncCounts()`'s own completion time.
///
/// The blocking window is a fixed, bounded duration (not an open-ended
/// gate released by the test) so a regression makes this test slow, never
/// hung — safe to run under `--parallel` alongside every other suite. (An
/// earlier version of this test used an open-ended gate and, run against
/// the pre-fix implementation, genuinely deadlocked the whole process —
/// `NSMainQueueConcurrencyType.perform` dispatches onto the real process
/// main thread, and a synchronous busy-wait there starves anything else
/// that also needs it. Bounded duration avoids that risk entirely.)
@Suite("TaskStore.syncCounts — L3 off the main-queue viewContext")
struct TaskStoreSyncCountsL3Tests {
    @Test("syncCounts does not wait behind a bounded viewContext-occupying operation")
    func syncCountsDoesNotWaitOnBusyViewContext() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "A")
        _ = try await store.create(title: "B")

        let view = p.container.viewContext
        let blockDuration: TimeInterval = 0.4

        // Occupy the viewContext's serial queue for a fixed, bounded window.
        let blockingTask = Task {
            await view.perform {
                Thread.sleep(forTimeInterval: blockDuration)
            }
        }
        // Give the blocking perform a moment to actually start occupying
        // the queue before racing syncCounts against it.
        try await Task.sleep(nanoseconds: 50_000_000)

        let start = Date()
        let counts = try await store.syncCounts()
        let elapsed = Date().timeIntervalSince(start)

        await blockingTask.value

        #expect(counts.local == 2)
        #expect(elapsed < blockDuration / 2, "syncCounts took \(elapsed)s — it appears to have waited behind the busy viewContext (bound: \(blockDuration)s)")
    }
}
