import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("CascadeReaper")
struct CascadeReaperTests {
    @Test("Reaps task + child + grandchild + journal + attachment + notificationSpec")
    func reapsFullCascade() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let attach = AttachmentStore(persistence: p)

        let parent = try await tasks.create(title: "parent")
        let child = try await tasks.create(title: "child", parent: parent)
        _ = try await tasks.create(title: "grandchild", parent: child)
        let entryID = try await journals.appendNote(taskID: child, body: "note")
        _ = try await attach.addFile(taskID: child, filename: "a.bin", uti: "public.data", data: Data([1]))

        let ctx = p.container.viewContext
        let reapedCount: Int = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", parent as CVarArg)
            let root = try ctx.fetch(req).first!
            let ids = CascadeReaper.objectIDs(forDeleting: [root])
            return ids.count
        }
        // parent + child + grandchild (3 tasks) + 2 journal entries
        // (the appended note + the auto attachment-kind journal entry created by
        // AttachmentStore.addFile) + 1 attachment = 6 reachable objectIDs.
        #expect(reapedCount == 6)
        _ = entryID
    }

    @Test("Does not reap nullify targets (tags)")
    func excludesTags() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let tag = try await tags.create(name: "Keep", tintColor: "#00FF00")
        let task = try await tasks.create(title: "tagged")
        try await tasks.assignTag(taskID: task, tagID: tag)

        let ctx = p.container.viewContext
        let containsTag: Bool = try await ctx.perform {
            let treq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            treq.predicate = NSPredicate(format: "id == %@", task as CVarArg)
            let root = try ctx.fetch(treq).first!
            let ids = Set(CascadeReaper.objectIDs(forDeleting: [root]))
            // LillistCore.Tag is fully qualified to disambiguate from Testing.Tag.
            let tagReq = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            tagReq.predicate = NSPredicate(format: "id == %@", tag as CVarArg)
            let tagMO = try ctx.fetch(tagReq).first!
            return ids.contains(tagMO.objectID)
        }
        #expect(containsTag == false)
    }
}
