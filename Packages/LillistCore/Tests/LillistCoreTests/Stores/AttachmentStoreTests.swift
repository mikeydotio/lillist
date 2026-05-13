import Testing
import Foundation
@testable import LillistCore

@Suite("AttachmentStore")
struct AttachmentStoreTests {
    private func tinyPNG() -> Data {
        Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
            0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
            0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ])
    }

    @Test("Add image creates an attachment + a journal entry")
    func addImage() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addImage(
            taskID: taskID,
            filename: "snap.png",
            data: tinyPNG()
        )
        let att = try await store.fetch(id: attID)
        #expect(att.kind == .image)
        #expect(att.filename == "snap.png")
        #expect(att.byteSize > 0)
        let entries = try await journals.entries(forTask: taskID)
        let attEntry = entries.first(where: { $0.kind == .attachment })
        #expect(attEntry != nil)
    }

    @Test("Add file with arbitrary UTI")
    func addFile() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addFile(
            taskID: taskID,
            filename: "spec.txt",
            uti: "public.plain-text",
            data: "hello".data(using: .utf8)!
        )
        let att = try await store.fetch(id: attID)
        #expect(att.kind == .file)
        #expect(att.uti == "public.plain-text")
    }

    @Test("Add link preview stores URL metadata")
    func addLinkPreview() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com")!,
            title: "Example",
            description: "An example domain",
            thumbnailData: nil,
            faviconData: nil
        )
        let att = try await store.fetch(id: attID)
        #expect(att.kind == .linkPreview)
        #expect(att.filename == "https://example.com")
        #expect(att.linkPreviewJSON?.contains("example.com") == true)
    }

    @Test("List attachments for a task")
    func list() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        _ = try await store.addImage(taskID: taskID, filename: "a.png", data: tinyPNG())
        _ = try await store.addImage(taskID: taskID, filename: "b.png", data: tinyPNG())
        let list = try await store.attachments(forTask: taskID)
        #expect(list.count == 2)
    }

    @Test("Reject attachment exceeding hard cap (>500MB)")
    func hardCap() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let big = Data(count: 501 * 1024 * 1024)
        await #expect(throws: LillistError.self) {
            _ = try await store.addImage(taskID: taskID, filename: "huge.png", data: big)
        }
    }

    @Test("Delete attachment removes the row")
    func delete() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await store.addImage(taskID: taskID, filename: "x.png", data: tinyPNG())
        try await store.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}
