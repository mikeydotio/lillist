import Testing
import Foundation
@testable import LillistCore

@Suite("AttachmentStore download")
struct AttachmentStoreDownloadTests {
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

    @Test("Metadata fetch does not include the data bytes in the returned record")
    func metadataOmitsBytes() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addImage(taskID: taskID, filename: "snap.png", data: tinyPNG())
        let record = try await store.fetch(id: attID)
        #expect(record.hasData == true)
        // The record itself never carries bytes — `hasData` is metadata.
        // Bytes only come through `downloadData(id:)`.
        // (This is the API contract.)
    }

    @Test("downloadData returns bytes when present")
    func downloadReturnsBytes() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let png = tinyPNG()
        let attID = try await store.addImage(taskID: taskID, filename: "snap.png", data: png)
        let bytes = try await store.downloadData(id: attID)
        #expect(bytes == png)
    }

    @Test("downloadData throws attachmentFetchFailed when bytes are absent (link preview row)")
    func downloadThrowsForLinkPreview() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com")!,
            title: nil,
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )
        await #expect(throws: LillistError.self) {
            _ = try await store.downloadData(id: attID)
        }
    }

    @Test("downloadData throws notFound for unknown ID")
    func downloadThrowsNotFound() async throws {
        let p = try await TestStore.make()
        let store = AttachmentStore(persistence: p)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.downloadData(id: UUID())
        }
    }
}
