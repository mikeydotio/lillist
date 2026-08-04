import Testing
import Foundation
import CoreData
@testable import LillistCore

/// LIL-97 — completing a task cascades to its open descendants, so a
/// subtask never dangles open under a done parent (the exact "orphan"
/// scenario the story exists to reduce). Re-opening the root reopens
/// exactly the descendants the cascade closed (matched by `closedAt`,
/// same precision as `clearSoftDelete`'s `matchingDeletedAt`), restoring
/// each one's own prior status from its `statusChange` journal entry — a
/// child completed independently, before or after, is left alone.
@Suite("TaskStore cascade-complete")
struct TaskStoreCascadeCompleteTests {
    // MARK: - Close cascade

    @Test("Closing a parent closes its open child")
    func closesOpenChild() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)

        try await store.transition(id: parentID, to: .closed)

        let child = try await store.fetch(id: childID)
        #expect(child.status == .closed)
        #expect(child.closedAt != nil)
    }

    @Test("Closing a parent closes a multi-level subtree")
    func closesGrandchild() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let rootID = try await store.create(title: "root")
        let childID = try await store.create(title: "child", parent: rootID)
        let grandchildID = try await store.create(title: "grandchild", parent: childID)

        try await store.transition(id: rootID, to: .closed)

        let child = try await store.fetch(id: childID)
        let grandchild = try await store.fetch(id: grandchildID)
        #expect(child.status == .closed)
        #expect(grandchild.status == .closed)
    }

    @Test("Closing a parent does not touch an already-closed child")
    func alreadyClosedChildUntouched() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.transition(id: childID, to: .closed)
        let childClosedAtBefore = try await store.fetch(id: childID).closedAt

        try await store.transition(id: parentID, to: .closed)

        let child = try await store.fetch(id: childID)
        #expect(child.closedAt == childClosedAtBefore, "an independently-completed child's closedAt must not be overwritten by a later parent cascade")
    }

    @Test("Cascade does not recurse past an already-closed intermediate node")
    func cascadeStopsAtAlreadyClosedIntermediate() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let rootID = try await store.create(title: "root")
        let middleID = try await store.create(title: "middle", parent: rootID)
        // Close middle BEFORE leaf exists, so leaf is never swept into
        // middle's own cascade — this fixture isolates "an intermediate
        // that was ALREADY closed" from "a leaf this very cascade closed",
        // which a child created after (closing middle first, then adding
        // the open leaf under it) is the only honest way to construct: a
        // fresh subtask under an already-closed parent stays open — create
        // has no parent-status validation, only `assertParentNotTrashed`.
        try await store.transition(id: middleID, to: .closed)
        let leafID = try await store.create(title: "leaf", parent: middleID)

        try await store.transition(id: rootID, to: .closed)

        let leaf = try await store.fetch(id: leafID)
        #expect(leaf.status != .closed, "an open leaf under an already-independently-closed intermediate parent must not be swept up by a later, higher-level cascade")
    }

    @Test("Closing a parent skips a trashed child")
    func trashedChildSkipped() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.softDelete(id: childID)

        try await store.transition(id: parentID, to: .closed)

        let child = try await store.fetch(id: childID)
        #expect(child.status != .closed, "a trashed child must not be resurrected into closed status by a cascade")
    }

    @Test("Close cascade writes a per-descendant journal entry recording its own prior status")
    func journalEntryPerDescendant() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let startedChildID = try await store.create(title: "started child", parent: parentID)
        try await store.transition(id: startedChildID, to: .started)
        let blockedChildID = try await store.create(title: "blocked child", parent: parentID)
        try await store.transition(id: blockedChildID, to: .blocked)

        try await store.transition(id: parentID, to: .closed)

        let startedEntries = try await journals.entries(forTask: startedChildID)
        let blockedEntries = try await journals.entries(forTask: blockedChildID)
        let startedClose = startedEntries.last { $0.kind == .statusChange }
        let blockedClose = blockedEntries.last { $0.kind == .statusChange }
        #expect(startedClose?.body == "started → closed")
        #expect(blockedClose?.body == "blocked → closed")
    }

    @Test("Only the explicitly-transitioned root spawns a recurrence instance")
    func onlyRootSpawnsRecurrence() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await store.create(title: "recurring parent")
        _ = try await store.create(title: "one-off subtask", parent: seedID)
        _ = try await series.create(
            fromSeedTask: seedID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )

        try await store.transition(id: seedID, to: .closed)

        let roots = try await store.children(of: nil)
        let spawnedCount = roots.filter { $0.id != seedID && $0.title == "recurring parent" }.count
        #expect(spawnedCount == 1, "closing the seed must spawn exactly one next instance, not one per cascaded descendant")
    }

    @Test("Cascade terminates on a mutual parent-cycle")
    func cascadeTerminatesOnCycle() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let ctx = p.container.viewContext
        let aID = UUID()
        let bID = UUID()
        try await ctx.perform {
            let a = LillistTask(context: ctx)
            a.id = aID; a.title = "A"; a.status = .todo
            let b = LillistTask(context: ctx)
            b.id = bID; b.title = "B"; b.status = .todo
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        let completed: Bool? = HangGuard.run(timeout: 3) {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var threw = false
            Task {
                do { try await store.transition(id: aID, to: .closed) } catch { threw = true }
                sem.signal()
            }
            sem.wait()
            return !threw
        }

        #expect(completed == true, "cascade-close must terminate (and succeed) on a mutual parent-cycle")
    }

    // MARK: - Reopen cascade

    @Test("Reopening a parent reopens the descendants its own cascade closed")
    func reopenReopensCascadedChild() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.transition(id: parentID, to: .closed)

        try await store.transition(id: parentID, to: .todo)

        let child = try await store.fetch(id: childID)
        #expect(child.status != .closed)
        #expect(child.closedAt == nil)
    }

    @Test("Reopen restores each descendant's own prior status, not a blanket .todo")
    func reopenRestoresPriorStatus() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let startedChildID = try await store.create(title: "started child", parent: parentID)
        try await store.transition(id: startedChildID, to: .started)
        let blockedChildID = try await store.create(title: "blocked child", parent: parentID)
        try await store.transition(id: blockedChildID, to: .blocked)
        try await store.transition(id: parentID, to: .closed)

        try await store.transition(id: parentID, to: .todo)

        let startedChild = try await store.fetch(id: startedChildID)
        let blockedChild = try await store.fetch(id: blockedChildID)
        #expect(startedChild.status == .started)
        #expect(blockedChild.status == .blocked)
    }

    @Test("Reopen leaves a child completed BEFORE the cascade closed")
    func reopenLeavesIndependentlyCompletedChildClosed() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let independentChildID = try await store.create(title: "already done", parent: parentID)
        try await store.transition(id: independentChildID, to: .closed)
        try await Task.sleep(nanoseconds: 10_000_000)
        let laterChildID = try await store.create(title: "cascaded", parent: parentID)

        try await store.transition(id: parentID, to: .closed)
        try await store.transition(id: parentID, to: .todo)

        let independentChild = try await store.fetch(id: independentChildID)
        let laterChild = try await store.fetch(id: laterChildID)
        #expect(independentChild.status == .closed, "a child completed before the cascade must stay closed on reopen")
        #expect(laterChild.status != .closed, "a child the cascade itself closed must reopen")
    }

    @Test("Reopen leaves a child completed AFTER the cascade (independently, later) closed")
    func reopenLeavesLaterIndependentlyCompletedChildClosed() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let cascadedChildID = try await store.create(title: "cascaded", parent: parentID)
        try await store.transition(id: parentID, to: .closed)
        // Reopen just this one child independently, then let it close again
        // on its own — its closedAt no longer matches the parent's cascade.
        try await store.transition(id: cascadedChildID, to: .todo)
        try await store.transition(id: cascadedChildID, to: .closed)

        try await store.transition(id: parentID, to: .todo)

        let child = try await store.fetch(id: cascadedChildID)
        #expect(child.status == .closed, "a child independently re-closed after the cascade must not be swept up by the parent's reopen")
    }

    @Test("Reopen without a matching journal entry falls back to .todo")
    func reopenFallsBackToTodoWithoutJournalEntry() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.transition(id: childID, to: .started)
        try await store.transition(id: parentID, to: .closed)

        // Simulate a missing/cleared journal entry for the cascaded child by
        // deleting it via direct context manipulation — the store's own
        // `JournalStore.delete` deliberately refuses to remove a
        // system-generated `statusChange` entry ("system journal entries
        // cannot be deleted"), so bypassing it here is the only way to
        // construct this edge case, same rationale `TreeCycleGuardTests`
        // uses to build states no local mutation path can reach on its own.
        let ctx = p.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "task.id == %@ AND kindRaw == %d", childID as CVarArg, JournalEntryKind.statusChange.rawValue)
            for entry in try ctx.fetch(req) { ctx.delete(entry) }
            try ctx.save()
        }

        try await store.transition(id: parentID, to: .todo)

        let child = try await store.fetch(id: childID)
        #expect(child.status == .todo, "a missing journal entry must never block the reopen — falls back to .todo")
    }

    @Test("Reopen terminates on a mutual parent-cycle")
    func reopenTerminatesOnCycle() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let ctx = p.container.viewContext
        let aID = UUID()
        let bID = UUID()
        let now = Date()
        try await ctx.perform {
            let a = LillistTask(context: ctx)
            a.id = aID; a.title = "A"; a.status = .closed; a.closedAt = now
            let b = LillistTask(context: ctx)
            b.id = bID; b.title = "B"; b.status = .closed; b.closedAt = now
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        let completed: Bool? = HangGuard.run(timeout: 3) {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var threw = false
            Task {
                do { try await store.transition(id: aID, to: .todo) } catch { threw = true }
                sem.signal()
            }
            sem.wait()
            return !threw
        }

        #expect(completed == true, "cascade-reopen must terminate (and succeed) on a mutual parent-cycle")
    }

    // MARK: - Notifications

    @Test("Close cascade cancels a descendant's pending notification")
    func closeCascadeCancelsDescendantNotification() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let store = TaskStore(persistence: p)
        store.notificationScheduler = scheduler

        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.update(id: childID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: childID, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.addedCount() == 1)

        try await store.transition(id: parentID, to: .closed)

        #expect(await fake.pendingNotificationRequests().isEmpty, "the cascaded child's pending notification must be cancelled too")
    }

    @Test("Reopen cascade re-registers a descendant's future notification")
    func reopenCascadeReinstallsDescendantNotification() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let store = TaskStore(persistence: p)
        store.notificationScheduler = scheduler

        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.update(id: childID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: childID, anchor: .deadline, offsetMinutes: -10)
        try await store.transition(id: parentID, to: .closed)
        #expect(await fake.pendingNotificationRequests().isEmpty)

        try await store.transition(id: parentID, to: .todo)

        #expect(await fake.pendingNotificationRequests().count == 1, "the reopened child's future reminder must come back")
    }

    // MARK: - Cross-process (widget / Shortcuts share the same store method)

    @Test("A widget-style single transition call cascades identically to an app-triggered one")
    func widgetStyleTransitionCascades() async throws {
        // Extensions/LillistWidget's AdvanceTaskStatusFromWidget and the
        // Shortcuts action both call TaskStore.transition(id:to:) directly —
        // no separate code path exists for them, so this pins that the
        // cascade is inherited automatically rather than re-asserting it via
        // a duplicate call site that could drift.
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)

        try await store.transition(id: parentID, to: .closed)

        let child = try await store.fetch(id: childID)
        #expect(child.status == .closed)
    }
}
