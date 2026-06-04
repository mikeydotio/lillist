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
