import Testing
import Foundation
import CoreData
@testable import LillistCore

/// H5: `AttachmentStore` had no rollback discipline at all — every
/// mutating method called `context.save()` with no surrounding `do`/`catch`.
@Suite("AttachmentStore rollback on save failure")
struct AttachmentStoreRollbackTests {
    @Test("A failed updateLinkPreview rolls the viewContext back")
    func updateLinkPreviewRollsBack() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let attachmentStore = AttachmentStore(persistence: p)
        let taskID = try await taskStore.create(title: "T")
        let attachmentID = try await attachmentStore.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com")!,
            title: "Example",
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )
        let view = p.container.viewContext

        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<LillistCore.Attachment>(entityName: "Attachment")
            req.predicate = NSPredicate(format: "id == %@", attachmentID as CVarArg)
            let m = try! view.fetch(req).first!
            m.filename = "dirty-pin"
        }
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<LillistCore.Attachment>(entityName: "Attachment")
            req.predicate = NSPredicate(format: "id == %@", attachmentID as CVarArg)
            let m = try! bg.fetch(req).first!
            m.filename = "bg-edit"
            try! bg.save()
        }

        var threw = false
        do {
            try await attachmentStore.updateLinkPreview(
                id: attachmentID,
                metadata: LinkPreviewMetadata(title: "New Title", description: nil)
            )
        } catch {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false, "updateLinkPreview's catch must roll back the shared viewContext")
    }
}
