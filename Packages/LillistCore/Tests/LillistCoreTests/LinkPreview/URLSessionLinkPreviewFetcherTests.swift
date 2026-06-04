import Testing
import Foundation
@testable import LillistCore

@Suite("URLSessionLinkPreviewFetcher SSRF guards")
struct URLSessionLinkPreviewFetcherTests {
    // Happy path through the streaming reader.
    @Test("fetchHTML returns body for a small text/html response")
    func fetchHTMLHappyPath() async {
        let session = StubURLProtocol.session { url in
            guard url.path == "/page" else { return nil }
            let html = "<html><head><title>OK</title></head></html>"
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data(html.utf8))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/page")!)
        #expect(data != nil)
        #expect(String(data: data ?? Data(), encoding: .utf8)?.contains("OK") == true)
    }

    // linkpreview-1: blocked scheme never reaches the network.
    @Test("fetchHTML returns nil for a file:// URL without hitting the session")
    func fetchHTMLBlocksFileScheme() async {
        let session = StubURLProtocol.session { _ in
            Issue.record("Blocked URL must not reach the session")
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("x".utf8))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "file:///etc/passwd")!)
        #expect(data == nil)
    }

    // linkpreview-3: private host never reaches the network.
    @Test("fetchHTML returns nil for a 127.0.0.1 URL without hitting the session")
    func fetchHTMLBlocksLoopbackHost() async {
        let session = StubURLProtocol.session { _ in
            Issue.record("Blocked URL must not reach the session")
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("x".utf8))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "http://127.0.0.1/")!)
        #expect(data == nil)
    }

    @Test("fetchImage returns nil for a link-local metadata URL")
    func fetchImageBlocksLinkLocal() async {
        let session = StubURLProtocol.session { _ in
            Issue.record("Blocked URL must not reach the session")
            return .init(statusCode: 200, headers: ["Content-Type": "image/png"], body: Data([0x89, 0x50]))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchImage(url: URL(string: "http://169.254.169.254/latest/meta-data/")!)
        #expect(data == nil)
    }

    // linkpreview-2: a redirect to a blocked host is refused.
    @Test("fetchHTML refuses a 302 redirect to a private host")
    func fetchHTMLBlocksRedirectToPrivateHost() async {
        let session = StubURLProtocol.session { url in
            switch url.host {
            case "example.com":
                return .redirect(to: "http://127.0.0.1/secret")
            case "127.0.0.1":
                Issue.record("Redirect to a private host must be refused before the follow-up request")
                return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("leak".utf8))
            default:
                return nil
            }
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/start")!)
        #expect(data == nil)
    }

    // linkpreview-2: a redirect to another public host is allowed.
    @Test("fetchHTML follows a single 302 to a public host")
    func fetchHTMLFollowsPublicRedirect() async {
        let session = StubURLProtocol.session { url in
            switch (url.host, url.path) {
            case ("a.example", "/start"):
                return .redirect(to: "https://b.example/final")
            case ("b.example", "/final"):
                return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("<html>arrived</html>".utf8))
            default:
                return nil
            }
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://a.example/start")!)
        #expect(String(data: data ?? Data(), encoding: .utf8)?.contains("arrived") == true)
    }

    // linkpreview-2: too many hops is refused even when every hop is public.
    @Test("fetchHTML gives up after exceeding the redirect hop limit")
    func fetchHTMLEnforcesHopLimit() async {
        let session = StubURLProtocol.session { url in
            // Each hop redirects to the next index on a public host; the
            // chain is longer than redirectHopLimit so it must fail.
            let hop = Int(url.lastPathComponent) ?? 0
            return .redirect(to: "https://chain.example/\(hop + 1)")
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://chain.example/0")!)
        #expect(data == nil)
    }

    // linkpreview-2 / size cap: an oversize body is aborted mid-stream.
    @Test("fetchHTML returns nil when the body exceeds the 5 MB cap")
    func fetchHTMLAbortsOversizeBody() async {
        let oversize = Data(repeating: 0x41, count: LinkPreviewLimits.bodyCapBytes + 1024)
        let session = StubURLProtocol.session { url in
            guard url.path == "/big" else { return nil }
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: oversize)
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/big")!)
        #expect(data == nil)
    }

    @Test("fetchHTML accepts a body exactly at the cap")
    func fetchHTMLAcceptsBodyAtCap() async {
        let atCap = Data(repeating: 0x41, count: LinkPreviewLimits.bodyCapBytes)
        let session = StubURLProtocol.session { url in
            guard url.path == "/atcap" else { return nil }
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: atCap)
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/atcap")!)
        #expect(data?.count == LinkPreviewLimits.bodyCapBytes)
    }
}
