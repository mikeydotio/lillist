import Testing
import Foundation
import UserNotifications
@testable import LillistCore

/// CLAUDE.md mandates stress repetitions for any code that crosses actor
/// boundaries. `NotificationScheduler.reconcile(taskID:)` is the single
/// actor-isolated entry point every mutation funnels through; this suite
/// hammers it concurrently to prove its invariants hold under contention.
///
/// The load-bearing invariant is at-most-one default spec per
/// `(taskID, kind)`. `materializeDefaultSpecs` does a check-then-add
/// (`specs(forTask:)` → `add(...)`); two interleaved reconciles can both
/// miss the row and both attempt to insert.
///
/// ENFORCEMENT: the invariant is enforced in `NotificationSpecStore.add`
/// (Wave 3 `cloudkit-convergence`, merged): the default-kind guard returns
/// the existing survivor and self-heals any duplicate rows a prior race
/// created. This suite is the regression guard verifying that enforcement.
/// Do NOT "fix" a failure here by adding a lock or dedup inside the
/// scheduler's reconcile loop; the per-(task,kind) row guard in
/// `NotificationSpecStore` is the correct seam — restore it there.
@Suite("NotificationScheduler — concurrent reconcile stress", .serialized)
struct NotificationSchedulerConcurrentReconcileTests {
    /// High iteration count per CLAUDE.md "add stress repetitions for any
    /// code that crosses actor boundaries". Each iteration spins a fresh
    /// store so a leaked spec from one round can't mask a bug in the next.
    private static let iterations = 50
    private static let concurrentReconciles = 16

    /// Build a scheduler over a fresh in-memory store with a single
    /// deadline-bearing task, returning the parts a test needs.
    private static func makeFixture() async throws -> (
        scheduler: NotificationScheduler,
        specs: NotificationSpecStore,
        fake: FakeUserNotificationCenter,
        taskID: UUID
    ) {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "stress-dev",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let taskID = try await tasks.create(title: "T")
        // Deadline 1h out with explicit time so the default-deadline spec
        // materializes and the computed fire date is in the future.
        let deadline = Date().addingTimeInterval(3600)
        try await tasks.update(id: taskID) { d in
            d.deadline = deadline
            d.deadlineHasTime = true
        }
        return (scheduler, specs, fake, taskID)
    }

    @Test("Concurrent reconciles of one task materialize exactly one default-deadline spec")
    func concurrentReconcileSingleDefaultSpec() async throws {
        for iteration in 0..<Self.iterations {
            let f = try await Self.makeFixture()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<Self.concurrentReconciles {
                    group.addTask {
                        await f.scheduler.reconcile(taskID: f.taskID)
                    }
                }
            }

            let allSpecs = try await f.specs.specs(forTask: f.taskID)
            let defaultDeadlineSpecs = allSpecs.filter { $0.kind == .defaultDeadline }
            #expect(
                defaultDeadlineSpecs.count == 1,
                "iteration \(iteration): expected exactly one defaultDeadline spec, got \(defaultDeadlineSpecs.count)"
            )
        }
    }

    @Test("After concurrent reconciles, exactly one pending request is scheduled for the task")
    func concurrentReconcileSinglePendingRequest() async throws {
        for iteration in 0..<Self.iterations {
            let f = try await Self.makeFixture()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<Self.concurrentReconciles {
                    group.addTask {
                        await f.scheduler.reconcile(taskID: f.taskID)
                    }
                }
            }

            let pending = await f.fake.pendingNotificationRequests()
            let forTask = pending.filter {
                ($0.content.userInfo["taskID"] as? String) == f.taskID.uuidString
            }
            #expect(
                forTask.count == 1,
                "iteration \(iteration): expected one pending request, got \(forTask.count)"
            )
        }
    }

    @Test("Clearing the deadline under concurrent reconciles leaves no default spec and no pending request")
    func concurrentReconcileClearsDeadline() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "stress-dev",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600)
            d.deadlineHasTime = true
        }
        // Materialize the default spec first.
        await scheduler.reconcile(taskID: taskID)
        #expect(try await specs.specs(forTask: taskID).filter { $0.kind == .defaultDeadline }.count == 1)

        // Now clear the deadline and hammer reconcile concurrently. Every
        // reconcile should converge on "no anchor → no default spec".
        try await tasks.update(id: taskID) { d in
            d.deadline = nil
            d.deadlineHasTime = false
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.concurrentReconciles {
                group.addTask { await scheduler.reconcile(taskID: taskID) }
            }
        }

        #expect(try await specs.specs(forTask: taskID).filter { $0.kind == .defaultDeadline }.isEmpty)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.filter { ($0.content.userInfo["taskID"] as? String) == taskID.uuidString }.isEmpty)
    }
}
