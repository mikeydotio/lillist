import Testing
import Foundation
import CoreData
@testable import LillistCore

/// M7: `Attachment.journalEntry` is a `Nullify` relationship
/// (`Model/LillistModel.xcdatamodeld` — verified directly against the
/// model), so deleting an `Attachment` alone leaves its auto-created
/// `JournalEntry` behind: a permanent blank system row nobody ever reaps
/// (the entry exists only to represent the attachment). `AttachmentStore
/// .delete` must delete the linked entry too.
@Suite("M7: AttachmentStore.delete reaps its auto-created JournalEntry")
struct AttachmentStoreM7OrphanedJournalEntryTests {
    @Test("Deleting an image attachment also deletes its auto-created journal entry")
    func deleteImageAttachmentDeletesJournalEntry() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let attachments = AttachmentStore(persistence: p)
        let journal = JournalStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let attachmentID = try await attachments.addImage(taskID: taskID, filename: "x.png", data: Data([0x01]))
        let record = try await attachments.fetch(id: attachmentID)
        let journalEntryID = try #require(record.journalEntryID)

        try await attachments.delete(id: attachmentID)

        await #expect(throws: LillistError.notFound) {
            _ = try await journal.fetch(id: journalEntryID)
        }
    }

    @Test("Deleting a link-preview attachment also deletes its auto-created journal entry")
    func deleteLinkPreviewAttachmentDeletesJournalEntry() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let attachments = AttachmentStore(persistence: p)
        let journal = JournalStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let attachmentID = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com")!,
            title: nil,
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )
        let record = try await attachments.fetch(id: attachmentID)
        let journalEntryID = try #require(record.journalEntryID)

        try await attachments.delete(id: attachmentID)

        await #expect(throws: LillistError.notFound) {
            _ = try await journal.fetch(id: journalEntryID)
        }
    }

    @Test("Deleting the attachment does not touch other journal entries on the same task")
    func deleteAttachmentLeavesUnrelatedEntriesIntact() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let attachments = AttachmentStore(persistence: p)
        let journal = JournalStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let noteID = try await journal.appendNote(taskID: taskID, body: "unrelated note")

        let attachmentID = try await attachments.addImage(taskID: taskID, filename: "x.png", data: Data([0x01]))
        try await attachments.delete(id: attachmentID)

        let note = try await journal.fetch(id: noteID)
        #expect(note.body == "unrelated note")
    }
}
