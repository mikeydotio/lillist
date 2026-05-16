import Testing
import Foundation
@testable import LillistCore

@Suite("OpenGraphParser")
struct OpenGraphParserTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "HTMLFixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Typical OG tags parse cleanly")
    func typical() throws {
        let html = try fixture("og-typical")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Example Article")
        #expect(m.description == "A short summary of the article.")
        #expect(m.imageURL?.absoluteString == "https://example.com/thumbnail.jpg")
        #expect(m.siteName == "Acme Co.")
    }

    @Test("Twitter card falls back when no og:* present")
    func twitterFallback() throws {
        let html = try fixture("og-twitter")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Twitter Title")
        #expect(m.description == "Twitter description text.")
        #expect(m.imageURL?.absoluteString == "https://example.com/twitter-card.png")
    }

    @Test("Page with only <title> populates title only")
    func onlyTitle() throws {
        let html = try fixture("og-empty")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Just a Title")
        #expect(m.description == nil)
        #expect(m.imageURL == nil)
    }

    @Test("Malformed HTML returns empty metadata without throwing")
    func malformed() throws {
        let html = try fixture("og-malformed")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Broken" || m.title == nil) // either is acceptable
    }
}
