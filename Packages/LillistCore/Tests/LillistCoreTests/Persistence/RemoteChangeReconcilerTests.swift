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
