import Testing
import Foundation
@testable import LillistCore

@Suite("DeepLink — parse & build")
struct DeepLinkTests {
    @Test("quickCapture round-trips")
    func quickCapture() {
        #expect(DeepLink(url: URL(string: "lillist://quickcapture")!) == .quickCapture)
        #expect(DeepLink.quickCapture.url.absoluteString == "lillist://quickcapture")
    }

    @Test("filter round-trips")
    func filter() {
        let id = UUID()
        #expect(DeepLink(url: DeepLink.filter(id).url) == .filter(id))
    }

    @Test("task round-trips")
    func task() {
        let id = UUID()
        #expect(DeepLink(url: DeepLink.task(id).url) == .task(id))
    }

    @Test("rejects a foreign scheme")
    func foreignScheme() {
        #expect(DeepLink(url: URL(string: "https://example.com/filter/x")!) == nil)
    }

    @Test("rejects a malformed uuid")
    func badUUID() {
        #expect(DeepLink(url: URL(string: "lillist://filter/not-a-uuid")!) == nil)
    }

    @Test("rejects an unknown host")
    func unknownHost() {
        #expect(DeepLink(url: URL(string: "lillist://frobnicate")!) == nil)
    }

    @Test("filter without an id is rejected")
    func filterNoID() {
        #expect(DeepLink(url: URL(string: "lillist://filter")!) == nil)
    }
}
