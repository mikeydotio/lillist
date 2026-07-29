import Testing
import Foundation
import CoreData
import os
@testable import LillistCore

/// C4/X4 — purge must delete via the managed-object graph (real
/// `context.delete(_:)` + `save()`), not `NSBatchDeleteRequest`, because
/// `NSPersistentCloudKitContainer` only tracks/exports deletions it
/// observes through a context save. A batch request executes as a direct
/// SQL delete via `context.execute(_:)` and never calls `save()` — no
/// `NSManagedObjectContextDidSave` notification fires for the affected
/// rows, which is exactly why the *old* code needed a synthetic
/// `NSManagedObjectContext.mergeChanges(fromRemoteContextSave:)` call
/// instead of ever observing one.
///
/// These tests assert that mechanism directly — a real
/// `NSManagedObjectContextDidSave` notification carrying the purged task's
/// objectID in `NSDeletedObjectsKey` — rather than only end-state (row
/// count), which `TaskStorePurgeAllTests`/`AutoPurgeJobTests` already cover
/// and which cannot by itself distinguish a batch delete from a context
/// delete (both leave the row count at zero).
@Suite("C4/X4 — purge deletes via a real context save, not NSBatchDeleteRequest")
struct C4X4PurgeMirroringTests {
    /// Observes every `.NSManagedObjectContextDidSave` notification posted
    /// during the test (object: nil matches saves from any context on any
    /// coordinator in the process) and records the union of every deleted
    /// object's objectID it has seen.
    ///
    /// `NotificationCenter` delivers to a `queue: nil` observer
    /// *synchronously*, on the posting thread — i.e. inside the very
    /// `ctx.perform { ...; try ctx.save() }` call the purge makes. A lock
    /// (matching `FakeUserNotificationCenter`'s established pattern), not an
    /// actor, keeps this capture fully synchronous with that post, so the
    /// assertion below needs no `Task.sleep` to "wait for delivery" — by the
    /// time `purgeAll()`/`AutoPurgeJob.run()` returns, the save (and thus the
    /// notification) has already happened.
    private final class SaveNotificationCapture: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock<Set<NSManagedObjectID>>(initialState: [])

        func record(_ ids: Set<NSManagedObjectID>) {
            lock.withLock { $0.formUnion(ids) }
        }

        var deletedObjectIDs: Set<NSManagedObjectID> {
            lock.withLock { $0 }
        }
    }

    private func observeDeletions(_ capture: SaveNotificationCapture) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { note in
            guard let deleted = note.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> else { return }
            capture.record(Set(deleted.map(\.objectID)))
        }
    }

    @Test("purgeAll's deletion arrives via a real NSManagedObjectContextDidSave")
    func purgeAllUsesContextSave() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "doomed")
        try await store.softDelete(id: id)

        let objectID: NSManagedObjectID = try await p.container.viewContext.perform {
            let req = NSFetchRequest<NSManagedObjectID>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.resultType = .managedObjectIDResultType
            guard let found = try p.container.viewContext.fetch(req).first else {
                throw LillistError.notFound
            }
            return found
        }

        let capture = SaveNotificationCapture()
        let observer = observeDeletions(capture)
        defer { NotificationCenter.default.removeObserver(observer) }

        let purged = try await store.purgeAll()
        #expect(purged == 1)

        let captured = capture.deletedObjectIDs
        #expect(
            captured.contains(objectID),
            """
            purgeAll must delete via a real context save (NSManagedObjectContextDidSave carrying \
            the purged row in NSDeletedObjectsKey) — NSBatchDeleteRequest never produces this signal, \
            which is the exact defect C4/X4 describes (purged rows never marked for CloudKit export)
            """
        )
    }

    @Test("AutoPurgeJob's deletion arrives via a real NSManagedObjectContextDidSave")
    func autoPurgeJobUsesContextSave() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 0 }
        let id = try await store.create(title: "doomed")
        try await store.softDelete(id: id)
        try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try p.container.viewContext.fetch(req).first!
            m.deletedAt = Date().addingTimeInterval(-86_400)
            try p.container.viewContext.save()
        }

        let objectID: NSManagedObjectID = try await p.container.viewContext.perform {
            let req = NSFetchRequest<NSManagedObjectID>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.resultType = .managedObjectIDResultType
            guard let found = try p.container.viewContext.fetch(req).first else {
                throw LillistError.notFound
            }
            return found
        }

        let capture = SaveNotificationCapture()
        let observer = observeDeletions(capture)
        defer { NotificationCenter.default.removeObserver(observer) }

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run()
        #expect(purged == 1)

        let captured = capture.deletedObjectIDs
        #expect(
            captured.contains(objectID),
            "AutoPurgeJob must delete via a real context save, same rationale as purgeAll above"
        )
    }
}
