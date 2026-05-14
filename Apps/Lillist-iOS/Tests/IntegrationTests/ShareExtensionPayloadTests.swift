import XCTest
import Foundation
import LillistCore

/// End-to-end check mirroring what `ShareRootView.save()` does on submit:
/// decode the payload → create a task → attach the URL (when present).
/// SharePayload is co-compiled into this test bundle (see project.yml).
final class ShareExtensionPayloadTests: XCTestCase {
    func test_url_payload_creates_a_task_with_a_link_attachment() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)
        let attachmentStore = AttachmentStore(persistence: persistence)

        let url = URL(string: "https://example.com/article")!
        let payload = SharePayload(items: [.url(url)])
        let decoded = try await payload.decode()

        let taskID = try await taskStore.create(title: decoded.suggestedTitle, notes: decoded.notes ?? "")
        if let url = decoded.url {
            _ = try await attachmentStore.addLinkPreview(
                taskID: taskID,
                url: url,
                title: nil,
                description: nil,
                thumbnailData: nil,
                faviconData: nil
            )
        }

        let attachments = try await attachmentStore.attachments(forTask: taskID)
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0].kind, .linkPreview)
        XCTAssertEqual(attachments[0].filename, url.absoluteString)
    }

    func test_text_plus_url_payload_creates_task_with_both_title_and_link_attachment() async throws {
        // Mirrors `ShareRootView.save()` when the inbound payload carries
        // both a text snippet and a URL — e.g. sharing a tweet that wraps
        // a link. Title comes from the text; the URL becomes a link
        // attachment so the user can come back to it.
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)
        let attachmentStore = AttachmentStore(persistence: persistence)

        let url = URL(string: "https://example.com/article")!
        let payload = SharePayload(items: [
            .text("Read later: an interesting article"),
            .url(url)
        ])
        let decoded = try await payload.decode()

        let taskID = try await taskStore.create(
            title: decoded.suggestedTitle,
            notes: decoded.notes ?? ""
        )
        if let url = decoded.url {
            _ = try await attachmentStore.addLinkPreview(
                taskID: taskID,
                url: url,
                title: nil,
                description: nil,
                thumbnailData: nil,
                faviconData: nil
            )
        }

        let task = try await taskStore.fetch(id: taskID)
        XCTAssertEqual(task.title, "Read later: an interesting article")
        let attachments = try await attachmentStore.attachments(forTask: taskID)
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0].kind, .linkPreview)
        XCTAssertEqual(attachments[0].filename, url.absoluteString)
    }

    func test_long_text_payload_keeps_full_body_in_notes() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)

        let long = String(repeating: "Need to remember this. ", count: 30)
        let payload = SharePayload(items: [.text(long)])
        let decoded = try await payload.decode()

        let taskID = try await taskStore.create(
            title: decoded.suggestedTitle,
            notes: decoded.notes ?? ""
        )
        let record = try await taskStore.fetch(id: taskID)
        XCTAssertLessThanOrEqual(record.title.count, 80)
        XCTAssertEqual(record.notes, long.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
