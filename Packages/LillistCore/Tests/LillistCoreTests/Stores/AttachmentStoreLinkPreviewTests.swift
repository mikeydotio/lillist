import Testing
import Foundation
@testable import LillistCore

@Suite("AttachmentStore.updateLinkPreview")
struct AttachmentStoreLinkPreviewTests {
    @Test("Updating writes title/description/thumbnail bytes through")
    func roundTrip() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")
        let attachmentID = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/x")!,
            title: nil,
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )

        try await attachments.updateLinkPreview(
            id: attachmentID,
            metadata: LinkPreviewMetadata(
                title: "Example",
                description: "Body",
                imageURL: URL(string: "https://example.com/thumb.jpg"),
                siteName: "Example"
            ),
            thumbnailData: Data([0xff, 0xd8, 0xff])
        )

        let updated = try await attachments.fetch(id: attachmentID)
        let payload = try #require(updated.linkPreviewJSON.flatMap { $0.data(using: .utf8) })
        let decoded = try JSONDecoder().decode(AttachmentStore.LinkPreviewPayload.self, from: payload)
        #expect(decoded.title == "Example")
        #expect(decoded.description == "Body")
        #expect(updated.hasData == true)
    }

    @Test("Updating with nil metadata only updates thumbnail data")
    func partialUpdate() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")
        let attachmentID = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/x")!,
            title: "Preset",
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )

        try await attachments.updateLinkPreview(
            id: attachmentID,
            metadata: LinkPreviewMetadata(),
            thumbnailData: Data([0x89, 0x50])
        )

        let updated = try await attachments.fetch(id: attachmentID)
        #expect(updated.hasData == true)
    }
}
