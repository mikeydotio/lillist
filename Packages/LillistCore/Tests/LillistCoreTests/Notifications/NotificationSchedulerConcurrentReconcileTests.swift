import Testing
import Foundation
import UserNotifications
@testable import LillistCore

/// CLAUDE.md mandates stress repetitions for any code that crosses actor
/// boundaries. `NotificationScheduler.reconcile(taskID:)` is the single
/// actor-isolated entry point every mutation funnels through; this suite
/// hammers it concurrently to prove its invariants hold under contention.
///
/// `NotificationScheduler` is an `actor`, but actors are *reentrant*: an
/// `await` inside `reconcile` can suspend and let another `reconcile` run,
/// so the two genuinely interleave. The concurrency-sensitive work is:
///   1. The pending add/remove loop (one pending request per user spec).
///   2. `purgeDefaultSpecs` — a check-then-delete that two interleaved
///      reconciles can both attempt on the same row.
/// (Lillist no longer auto-creates default specs, so the former
/// check-then-add race in `materializeDefaultSpecs` is gone.)
@Suite("NotificationScheduler — concurrent reconcile stress", .serialized)
struct NotificationSchedulerConcurrentReconcileTests {
    /// High iteration count per CLAUDE.md "add stress repetitions for any
    /// code that crosses actor boundaries". Each iteration spins a fresh
    /// store so a leaked spec from one round can't mask a bug in the next.
    private static let iterations = 50
    private static let concurrentReconciles = 16

    /// Build a scheduler over a fresh in-memory store with a single
    /// deadline-bearing task carrying one user offset reminder, returning
    /// the parts a test needs.
    private static func makeFixture() async throws -> (
        scheduler: NotificationScheduler,
        tasks: TaskStore,
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
        // Deadline 1h out with explicit time + a user offset reminder so the
        // computed fire date is in the future and one pending request is due.
        let deadline = Date().addingTimeInterval(3600)
        try await tasks.update(id: taskID) { d in
            d.deadline = deadline
            d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        return (scheduler, tasks, specs, fake, taskID)
    }

    @Test("Concurrent reconciles purge a legacy default spec, converging to zero")
    func concurrentReconcilePurgesLegacyDefault() async throws {
        for iteration in 0..<Self.iterations {
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
                d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
            }
            // A legacy default spec from before defaults were removed.
            _ = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<Self.concurrentReconciles {
                    group.addTask { await scheduler.reconcile(taskID: taskID) }
                }
            }

            let defaultDeadlineSpecs = try await specs.specs(forTask: taskID).filter { $0.kind == .defaultDeadline }
            #expect(
                defaultDeadlineSpecs.isEmpty,
                "iteration \(iteration): expected the legacy default purged, got \(defaultDeadlineSpecs.count)"
            )
            let pending = await fake.pendingNotificationRequests()
            #expect(
                pending.filter { ($0.content.userInfo["taskID"] as? String) == taskID.uuidString }.isEmpty,
                "iteration \(iteration): expected no pending for the purged default"
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

    @Test("Clearing the deadline under concurrent reconciles leaves no pending request")
    func concurrentReconcileClearsDeadline() async throws {
        let f = try await Self.makeFixture()
        // The offset reminder is scheduled while the deadline exists.
        await f.scheduler.reconcile(taskID: f.taskID)
        #expect(await f.fake.pendingNotificationRequests().filter {
            ($0.content.userInfo["taskID"] as? String) == f.taskID.uuidString
        }.count == 1)

        // Now clear the deadline and hammer reconcile concurrently. With no
        // anchor, the offset reminder can't compute a fire date, so every
        // reconcile should converge on "no pending request".
        try await f.tasks.update(id: f.taskID) { d in
            d.deadline = nil
            d.deadlineHasTime = false
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.concurrentReconciles {
                group.addTask { await f.scheduler.reconcile(taskID: f.taskID) }
            }
        }

        let pending = await f.fake.pendingNotificationRequests()
        #expect(pending.filter { ($0.content.userInfo["taskID"] as? String) == f.taskID.uuidString }.isEmpty)
    }
}
