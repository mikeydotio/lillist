import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge attach/link/nudge")
struct AttachLinkNudgeHandlerTests {
    @Test("Attach reads files and records attachments")
    func attach() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lillist-attach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.txt")
        try "hi".data(using: .utf8)!.write(to: file)
        let attached = try await CLIBridge.AttachHandler.run(token: id.uuidString, paths: [file.path], persistence: p)
        #expect(attached.count == 1)
        let recs = try await AttachmentStore(persistence: p).attachments(forTask: id)
        #expect(recs.count == 1)
        #expect(recs[0].filename == "note.txt")
    }

    @Test("Attach with empty paths throws validationFailed")
    func attachEmpty() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.AttachHandler.run(token: id.uuidString, paths: [], persistence: p)
        }
    }

    @Test("Link adds a linkPreview attachment with the URL")
    func link() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        let attID = try await CLIBridge.LinkHandler.run(token: id.uuidString, urlString: "https://example.com/", persistence: p)
        let recs = try await AttachmentStore(persistence: p).attachments(forTask: id)
        #expect(recs.contains { $0.id == attID })
        #expect(recs.contains { $0.kind == .linkPreview })
    }

    @Test("Link rejects malformed URL")
    func linkInvalid() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.LinkHandler.run(token: id.uuidString, urlString: "not a url", persistence: p)
        }
    }

    @Test("Nudge writes a NotificationSpec of kind .nudge with fireDate")
    func nudge() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        let specID = try await CLIBridge.NudgeHandler.run(
            token: id.uuidString, atToken: "+1d",
            persistence: p, now: Date(), calendar: .current
        )
        let specs = try await NotificationSpecStore(persistence: p).specs(forTask: id)
        #expect(specs.contains { $0.id == specID && $0.kind == .nudge && $0.fireDate != nil })
    }
}
