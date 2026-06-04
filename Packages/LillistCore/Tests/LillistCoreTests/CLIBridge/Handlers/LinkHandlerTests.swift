import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.LinkHandler")
struct LinkHandlerTests {
    @Test("Run with a stub fetcher populates the attachment's title")
    func runWithStubFetcher() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")

        let session = StubURLProtocol.session { _ in
            let html = #"""
            <html><head>
            <meta property="og:title" content="Linked Title">
            </head><body></body></html>
            """#
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: html.data(using: .utf8)!)
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)

        let attachmentID = try await CLIBridge.LinkHandler.run(
            token: taskID.uuidString,
            urlString: "https://example.com/x",
            persistence: persistence,
            fetcher: fetcher
        )

        let row = try await AttachmentStore(persistence: persistence).fetch(id: attachmentID)
        let bytes = try #require(row.linkPreviewJSON.flatMap { $0.data(using: .utf8) })
        let decoded = try JSONDecoder().decode(AttachmentStore.LinkPreviewPayload.self, from: bytes)
        #expect(decoded.title == "Linked Title")
    }

    @Test("Run rejects a non-http/https URL at the ingest boundary")
    func runRejectsBlockedScheme() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")

        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.LinkHandler.run(
                token: taskID.uuidString,
                urlString: "file:///etc/passwd",
                persistence: persistence,
                fetcher: nil
            )
        }
    }

    @Test("Run rejects a private-host URL and creates no attachment")
    func runRejectsPrivateHost() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")

        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.LinkHandler.run(
                token: taskID.uuidString,
                urlString: "http://169.254.169.254/latest/meta-data/",
                persistence: persistence,
                fetcher: nil
            )
        }

        let attachments = try await AttachmentStore(persistence: persistence).attachments(forTask: taskID)
        #expect(attachments.isEmpty)
    }
}
