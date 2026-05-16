import Testing
import Foundation
@testable import LillistCore

@Suite("LinkPreviewUnfurler")
struct LinkPreviewUnfurlerTests {
    @Test("End-to-end: fetch, parse, update attachment")
    func endToEnd() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")
        let attachmentID = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/blog/post")!,
            title: nil, description: nil, thumbnailData: nil, faviconData: nil
        )

        let session = StubURLProtocol.session { url in
            switch url.path {
            case "/blog/post":
                let html = """
                <html><head><title>Hi</title>
                <meta property="og:title" content="Real Title">
                <meta property="og:description" content="Real Desc">
                <meta property="og:image" content="https://example.com/thumb.jpg">
                </head><body></body></html>
                """
                return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: html.data(using: .utf8)!)
            case "/thumb.jpg":
                return .init(statusCode: 200, headers: ["Content-Type": "image/jpeg"], body: Data([0xff, 0xd8, 0xff]))
            default:
                return nil
            }
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let unfurler = LinkPreviewUnfurler(attachments: attachments, fetcher: fetcher)

        let outcome = await unfurler.unfurl(attachmentID: attachmentID, url: URL(string: "https://example.com/blog/post")!)
        #expect(outcome == .success)

        let updated = try await attachments.fetch(id: attachmentID)
        let payload = try #require(updated.linkPreviewJSON.flatMap { $0.data(using: .utf8) })
        let decoded = try JSONDecoder().decode(AttachmentStore.LinkPreviewPayload.self, from: payload)
        #expect(decoded.title == "Real Title")
        #expect(updated.hasData == true)
    }

    @Test("Server 404 → outcome = .failure(.notFound), no metadata changes")
    func notFound() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "x")
        let aid = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/gone")!,
            title: nil, description: nil, thumbnailData: nil, faviconData: nil
        )

        let session = StubURLProtocol.session { _ in
            .init(statusCode: 404, headers: [:], body: Data())
        }
        let unfurler = LinkPreviewUnfurler(
            attachments: attachments,
            fetcher: URLSessionLinkPreviewFetcher(session: session)
        )

        let outcome = await unfurler.unfurl(attachmentID: aid, url: URL(string: "https://example.com/gone")!)
        if case .failure = outcome { /* pass */ } else { Issue.record("Expected .failure outcome") }

        let row = try await attachments.fetch(id: aid)
        let payload = try #require(row.linkPreviewJSON.flatMap { $0.data(using: .utf8) })
        let decoded = try JSONDecoder().decode(AttachmentStore.LinkPreviewPayload.self, from: payload)
        #expect(decoded.title == nil)
        #expect(decoded.description == nil)
        #expect(decoded.url == "https://example.com/gone") // affordance preserved
    }
}
