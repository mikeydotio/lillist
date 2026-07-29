import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("RemoteChangeReconciler")
struct RemoteChangeReconcilerTests {
    /// Build the entity-name → ObjectID-class metadata the diffing core uses,
    /// straight off a real (in-memory) store so the test exercises the actual
    /// model, not a hand-rolled stand-in.
    private func makeContext() async throws -> (PersistenceController, NSManagedObjectContext) {
        let p = try await TestStore.make()
        return (p, p.container.viewContext)
    }

    @Test("A foreign-author lastFiredAt change yields the spec's taskID")
    func importChangeYieldsTaskID() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        // Resolve the spec's objectID + its task's objectID so we can hand the
        // diffing core a synthetic change record keyed on them.
        let (specObjectID, taskObjectID) = try await ctx.perform { () -> (NSManagedObjectID, NSManagedObjectID) in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let m = try ctx.fetch(req).first!
            return (m.objectID, m.task!.objectID)
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: ["lastFiredAt"],
            author: "OtherDeviceImport"   // not our local author
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected == [taskID])
        _ = taskObjectID
    }

    @Test("A self-authored change is ignored")
    func selfAuthoredChangeIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        let specObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: ["lastFiredAt"],
            author: PersistenceController.localTransactionAuthor
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    @Test("A non-lastFiredAt property change on a spec is ignored")
    func unrelatedPropertyIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        let specObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: ["snoozedUntil"],   // not lastFiredAt
            author: "OtherDeviceImport"
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    @Test("A change to a non-NotificationSpec entity is ignored")
    func nonSpecEntityIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let taskObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: taskObjectID,
            entityName: "LillistTask",
            changedProperties: ["lastFiredAt"],
            author: "OtherDeviceImport"
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    // MARK: - H6: watermark advances only after the consuming work completes

    /// Actor spy so the reconciler's `@Sendable` callback can safely read
    /// `tokenStore.lastToken` (checking `nil`-ness only — no
    /// `NSPersistentHistoryToken` capture) at the moment it fires.
    private actor CallbackWatermarkSpy {
        private(set) var wasNilDuringCallback: Bool?
        private(set) var receivedIDs: [UUID] = []
        private let tokenStore: PersistentHistoryTokenStore
        init(tokenStore: PersistentHistoryTokenStore) { self.tokenStore = tokenStore }
        func record(_ ids: [UUID]) {
            wasNilDuringCallback = (tokenStore.lastToken == nil)
            receivedIDs.append(contentsOf: ids)
        }
    }

    /// Writes `lastFiredAt` through a background context stamped with a
    /// foreign author, so the write reads as a "remote import" the same way
    /// the two-store convergence test above does.
    private func writeForeignLastFired(specID: UUID, on persistence: PersistenceController) async throws {
        let foreignCtx = persistence.container.newBackgroundContext()
        foreignCtx.transactionAuthor = "OtherDevice.import"
        try await foreignCtx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let m = try foreignCtx.fetch(req).first!
            m.lastFiredAt = Date()
            try foreignCtx.save()
        }
    }

    @Test("H6: the watermark is not advanced until onAffectedTasks has completed")
    func watermarkAdvancesOnlyAfterCallbackCompletes() async throws {
        let (p, _) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)
        try await writeForeignLastFired(specID: specID, on: p)

        let tokenStore = PersistentHistoryTokenStore(suiteName: "H6-order-\(UUID().uuidString)")
        let spy = CallbackWatermarkSpy(tokenStore: tokenStore)
        let reconciler = RemoteChangeReconciler(persistence: p, tokenStore: tokenStore) { ids in
            await spy.record(ids)
        }

        await reconciler.processPendingHistory()

        let wasNil = await spy.wasNilDuringCallback
        #expect(wasNil == true, "the watermark must still be nil while onAffectedTasks is running — advance-after-work, not before")
        let received = await spy.receivedIDs
        #expect(received == [taskID])
        #expect(tokenStore.lastToken != nil, "the watermark must be written once processPendingHistory has returned")
    }

    @Test("H6: uses this controller's own transactionAuthor, not a hardcoded default, to classify local vs foreign writes")
    func usesInstanceTransactionAuthorNotHardcodedDefault() async throws {
        // A controller stamped with a NON-default author (mirroring the
        // macOS app's PersistenceController.macAppTransactionAuthor).
        // Before the H6 fix, the reconciler compared against the hardcoded
        // `localTransactionAuthor` ("Lillist.app"), so THIS controller's own
        // writes (stamped "Lillist.macApp") would be misclassified as foreign.
        let p = try await PersistenceController(
            configuration: .inMemory,
            transactionAuthor: PersistenceController.macAppTransactionAuthor
        )
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        // A write made through THIS SAME controller's own viewContext — i.e.
        // genuinely local to this process, stamped with its own transactionAuthor.
        try await p.container.viewContext.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let spec = try p.container.viewContext.fetch(req).first!
            spec.lastFiredAt = Date()
            try p.container.viewContext.save()
        }

        let tokenStore = PersistentHistoryTokenStore(suiteName: "H6-author-\(UUID().uuidString)")
        let spy = CallbackWatermarkSpy(tokenStore: tokenStore)
        let reconciler = RemoteChangeReconciler(persistence: p, tokenStore: tokenStore) { ids in
            await spy.record(ids)
        }

        await reconciler.processPendingHistory()

        let received = await spy.receivedIDs
        #expect(received.isEmpty, "a write authored by this controller's OWN transactionAuthor must be classified as local and never trigger reconcile")
    }

    // MARK: - M3: overlapping notifications don't double-process or regress the watermark

    @Test("M3: concurrent processPendingHistory calls process each change exactly once, no watermark regression")
    func concurrentCallsProcessEachChangeExactlyOnce() async throws {
        let (p, _) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        var taskIDs: [UUID] = []
        for i in 0..<8 {
            let taskID = try await tasks.create(title: "t\(i)")
            let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)
            try await writeForeignLastFired(specID: specID, on: p)
            taskIDs.append(taskID)
        }

        actor CallbackSpy {
            private(set) var received: [UUID] = []
            func record(_ ids: [UUID]) { received.append(contentsOf: ids) }
        }
        let spy = CallbackSpy()
        let tokenStore = PersistentHistoryTokenStore(suiteName: "M3-\(UUID().uuidString)")
        let reconciler = RemoteChangeReconciler(persistence: p, tokenStore: tokenStore) { ids in
            await spy.record(ids)
        }

        // Fire many overlapping drains at once — the reentrancy guard must let
        // exactly one run and coalesce the rest, so no task id is reconciled
        // more than once and the watermark never regresses under the flood.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<24 { group.addTask { await reconciler.processPendingHistory() } }
        }

        let received = await spy.received
        #expect(Set(received).count == received.count, "no task id may be reconciled more than once across overlapping notifications")
        #expect(Set(received) == Set(taskIDs), "every affected task must be reconciled exactly once")

        // A subsequent call with no new writes must trigger nothing further —
        // proves the watermark did not regress under the concurrent flood.
        await reconciler.processPendingHistory()
        let receivedAfter = await spy.received
        #expect(receivedAfter.count == received.count, "a settled pass after the flood must not re-trigger any callback")
    }

    @Test("Duplicate taskIDs across multiple specs collapse to a unique set")
    func deduplicatesTaskIDs() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        // Two distinct specs on the same task (one default, one offset).
        let s1 = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        let s2 = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -10, fireDate: nil)

        let ids = try await ctx.perform { () -> [NSManagedObjectID] in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id IN %@", [s1, s2])
            return try ctx.fetch(req).map(\.objectID)
        }
        let changes = ids.map {
            RemoteChangeReconciler.SyntheticChange(
                changedObjectID: $0,
                entityName: "NotificationSpec",
                changedProperties: ["lastFiredAt"],
                author: "OtherDeviceImport"
            )
        }

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: changes,
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected == [taskID])
    }

    // MARK: - X9: widened diffing (spec insert/delete, task soft-delete/restore)

    @Test("X9: a foreign-author NotificationSpec insert yields the spec's taskID")
    func specInsertYieldsTaskID() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .offsetDeadline, offsetMinutes: -10, fireDate: nil)

        let specObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: [],   // inserts don't populate updatedProperties
            author: "OtherDeviceImport",
            changeType: .insert
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected == [taskID], "an inserted spec (a reminder added on another device) must reconcile the owning task so it schedules here too")
    }

    @Test("X9: a self-authored NotificationSpec insert is ignored")
    func specInsertSelfAuthoredIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .offsetDeadline, offsetMinutes: -10, fireDate: nil)

        let specObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: [],
            author: PersistenceController.localTransactionAuthor,
            changeType: .insert
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    @Test("X9: a NotificationSpec delete yields no taskID (unresolvable from history — handled by the orphan sweep instead)")
    func specDeleteYieldsNoTaskID() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        // A deleted row's objectID is still a valid NSManagedObjectID value
        // (just unresolvable via existingObject(with:)) — construct one from
        // the task itself; entityName is what the diffing core switches on,
        // not the specific dead objectID.
        let deadObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: deadObjectID,
            entityName: "NotificationSpec",
            changedProperties: [],
            author: "OtherDeviceImport",
            changeType: .delete
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    @Test("X9: hasForeignSpecDeletions detects a foreign NotificationSpec delete")
    func hasForeignSpecDeletionsDetectsDelete() throws {
        let dummy = NSManagedObjectID()
        let foreignDelete = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: dummy, entityName: "NotificationSpec",
            changedProperties: [], author: "OtherDevice", changeType: .delete
        )
        #expect(RemoteChangeReconciler.hasForeignSpecDeletions(
            in: [foreignDelete], localAuthor: PersistenceController.localTransactionAuthor
        ))
    }

    @Test("X9: hasForeignSpecDeletions ignores a self-authored delete")
    func hasForeignSpecDeletionsIgnoresSelfAuthored() throws {
        let dummy = NSManagedObjectID()
        let ownDelete = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: dummy, entityName: "NotificationSpec",
            changedProperties: [], author: PersistenceController.localTransactionAuthor, changeType: .delete
        )
        #expect(RemoteChangeReconciler.hasForeignSpecDeletions(
            in: [ownDelete], localAuthor: PersistenceController.localTransactionAuthor
        ) == false)
    }

    @Test("X9: hasForeignSpecDeletions ignores a delete on a different entity")
    func hasForeignSpecDeletionsIgnoresOtherEntity() throws {
        let dummy = NSManagedObjectID()
        let taskDelete = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: dummy, entityName: "LillistTask",
            changedProperties: [], author: "OtherDevice", changeType: .delete
        )
        #expect(RemoteChangeReconciler.hasForeignSpecDeletions(
            in: [taskDelete], localAuthor: PersistenceController.localTransactionAuthor
        ) == false)
    }

    @Test("X9: a foreign-author task soft-delete (deletedAt set) yields the task's own id")
    func taskSoftDeleteYieldsTaskID() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let taskObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: taskObjectID,
            entityName: "LillistTask",
            changedProperties: ["deletedAt"],
            author: "OtherDeviceImport",
            changeType: .update
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected == [taskID], "a task trashed on another device must reconcile locally so its now-empty desired set cancels the pending request")
    }

    @Test("X9: a foreign-author task restore (deletedAt cleared) yields the task's own id")
    func taskRestoreYieldsTaskID() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        try await tasks.softDelete(id: taskID)

        let taskObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: taskObjectID,
            entityName: "LillistTask",
            changedProperties: ["deletedAt"],
            author: "OtherDeviceImport",
            changeType: .update
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected == [taskID], "a task restored on another device must reconcile locally so its reminders can be re-installed")
    }

    @Test("X9: a task update NOT touching deletedAt is ignored")
    func taskUpdateWithoutDeletedAtIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let taskObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: taskObjectID,
            entityName: "LillistTask",
            changedProperties: ["title"],
            author: "OtherDeviceImport",
            changeType: .update
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty, "an ordinary title edit on another device is not a notification-relevant change")
    }

    // MARK: - X9: end-to-end wiring through processPendingHistory

    /// Deletes a NotificationSpec through a background context stamped with
    /// a foreign author, mirroring `writeForeignLastFired`'s shape.
    private func deleteForeignSpec(specID: UUID, on persistence: PersistenceController) async throws {
        let foreignCtx = persistence.container.newBackgroundContext()
        foreignCtx.transactionAuthor = "OtherDevice.import"
        try await foreignCtx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let m = try foreignCtx.fetch(req).first!
            foreignCtx.delete(m)
            try foreignCtx.save()
        }
    }

    @Test("X9: processPendingHistory fires onOrphanedSpecDeletions for a foreign spec delete")
    func processPendingHistoryFiresOrphanCallback() async throws {
        let (p, _) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .offsetDeadline, offsetMinutes: -10, fireDate: nil)
        try await deleteForeignSpec(specID: specID, on: p)

        actor OrphanSpy {
            private(set) var callCount = 0
            func record() { callCount += 1 }
        }
        let spy = OrphanSpy()
        let tokenStore = PersistentHistoryTokenStore(suiteName: "X9-orphan-\(UUID().uuidString)")
        let reconciler = RemoteChangeReconciler(
            persistence: p, tokenStore: tokenStore,
            onAffectedTasks: { _ in }
        ) {
            await spy.record()
        }

        await reconciler.processPendingHistory()

        #expect(await spy.callCount == 1)
    }

    @Test("X9: processPendingHistory does NOT fire onOrphanedSpecDeletions for a self-authored spec delete")
    func processPendingHistoryIgnoresSelfAuthoredDelete() async throws {
        let (p, _) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .offsetDeadline, offsetMinutes: -10, fireDate: nil)
        try await specs.delete(id: specID)   // deleted through the local (own-author) context

        actor OrphanSpy {
            private(set) var callCount = 0
            func record() { callCount += 1 }
        }
        let spy = OrphanSpy()
        let tokenStore = PersistentHistoryTokenStore(suiteName: "X9-orphan-self-\(UUID().uuidString)")
        let reconciler = RemoteChangeReconciler(
            persistence: p, tokenStore: tokenStore,
            onAffectedTasks: { _ in }
        ) {
            await spy.record()
        }

        await reconciler.processPendingHistory()

        #expect(await spy.callCount == 0)
    }

    @Test("X9: processPendingHistory reconciles a task soft-deleted through a foreign context")
    func processPendingHistoryFiresForForeignTaskSoftDelete() async throws {
        let (p, _) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let foreignCtx = p.container.newBackgroundContext()
        foreignCtx.transactionAuthor = "OtherDevice.import"
        try await foreignCtx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            let m = try foreignCtx.fetch(req).first!
            m.deletedAt = Date()
            try foreignCtx.save()
        }

        actor CallbackSpy {
            private(set) var received: [UUID] = []
            func record(_ ids: [UUID]) { received.append(contentsOf: ids) }
        }
        let spy = CallbackSpy()
        let tokenStore = PersistentHistoryTokenStore(suiteName: "X9-tasksoftdelete-\(UUID().uuidString)")
        let reconciler = RemoteChangeReconciler(persistence: p, tokenStore: tokenStore) { ids in
            await spy.record(ids)
        }

        await reconciler.processPendingHistory()

        #expect(await spy.received == [taskID])
    }
}

@Suite("Two-store convergence (shared on-disk file)")
struct TwoStoreConvergenceTests {
    /// A unique temp .sqlite path; cleaned up by the test.
    private static func tempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LillistConvergence-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Lillist.sqlite")
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Both controllers over one file see exactly one AppPreferences row after normalization")
    func preferencesConvergeToOneRow() async throws {
        let url = Self.tempStoreURL()
        defer { Self.cleanup(url) }

        // LocalOnly keeps the runtime path off live CloudKit while still using
        // the on-disk store + history tracking the convergence relies on.
        let cfgA = StoreConfiguration.onDisk(url: url, syncMode: .localOnly)
        let a = try await PersistenceController(configuration: cfgA)
        let prefsA = PreferencesStore(persistence: a)
        _ = try await prefsA.read()   // materialize the canonical row on A

        let cfgB = StoreConfiguration.onDisk(url: url, syncMode: .localOnly)
        let b = try await PersistenceController(configuration: cfgB)
        let prefsB = PreferencesStore(persistence: b)
        _ = try await prefsB.read()   // B must adopt the same well-known id

        try await prefsA.normalizeSingletons()
        try await prefsB.normalizeSingletons()

        #expect(try await prefsA.rowCount() == 1)
        #expect(try await prefsB.rowCount() == 1)
    }

    @Test("A lastFiredAt write on store A surfaces the task via the reconciler diff on store B")
    func lastFiredConvergence() async throws {
        let url = Self.tempStoreURL()
        defer { Self.cleanup(url) }

        let a = try await PersistenceController(configuration: .onDisk(url: url, syncMode: .localOnly))
        let tasksA = TaskStore(persistence: a)
        let specsA = NotificationSpecStore(persistence: a)
        let taskID = try await tasksA.create(title: "Sync me")
        let specID = try await specsA.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        // Open "device B" over the same file and let it see A's rows.
        let b = try await PersistenceController(configuration: .onDisk(url: url, syncMode: .localOnly))
        let bCtx = b.container.viewContext

        // Snapshot B's history watermark BEFORE A writes lastFiredAt, so the
        // diff covers exactly the new transaction.
        let tokenStore = PersistentHistoryTokenStore(suiteName: "TwoStore-\(UUID().uuidString)")
        tokenStore.lastToken = try await bCtx.perform {
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            let result = try bCtx.execute(req) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
        }

        // Device A records the fire (a different author than B's localAuthor —
        // both are "Lillist.app" here, so to model a *foreign* import we write
        // through a throwaway author on a background context).
        let foreignCtx = a.container.newBackgroundContext()
        foreignCtx.transactionAuthor = "DeviceA.import"
        try await foreignCtx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let m = try foreignCtx.fetch(req).first!
            m.lastFiredAt = Date(timeIntervalSince1970: 9_000_000)
            try foreignCtx.save()
        }

        // Pull A's change into B and run the reconciler diff against the new
        // history. A short poll absorbs cross-coordinator merge latency.
        var affected: [UUID] = []
        for _ in 0..<50 {
            await bCtx.perform { bCtx.refreshAllObjects() }
            let changes: [RemoteChangeReconciler.SyntheticChange] = try await bCtx.perform {
                // Read the watermark inside the perform block so the non-Sendable
                // NSPersistentHistoryToken is never captured across the @Sendable
                // boundary (Swift 6 strict concurrency); tokenStore is Sendable.
                let after = tokenStore.lastToken
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
                guard let result = try bCtx.execute(request) as? NSPersistentHistoryResult,
                      let txns = result.result as? [NSPersistentHistoryTransaction] else { return [] }
                var out: [RemoteChangeReconciler.SyntheticChange] = []
                for txn in txns {
                    for change in txn.changes ?? [] {
                        out.append(.init(
                            changedObjectID: change.changedObjectID,
                            entityName: change.changedObjectID.entity.name ?? "",
                            changedProperties: change.updatedProperties.map { Set($0.map(\.name)) } ?? [],
                            author: txn.author
                        ))
                    }
                }
                return out
            }
            affected = try await RemoteChangeReconciler.affectedTaskIDs(
                from: changes,
                localAuthor: PersistenceController.localTransactionAuthor,
                in: bCtx
            )
            if affected.isEmpty == false { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(affected == [taskID])
    }
}
