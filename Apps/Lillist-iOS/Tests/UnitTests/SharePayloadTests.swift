import XCTest
import Foundation

/// Exercises `SharePayload.decode()` against typical inbound items.
/// SharePayload is co-compiled into this test bundle (see project.yml) so
/// the test can construct payloads via the `items:` test seam without a
/// running NSExtensionContext.
final class SharePayloadTests: XCTestCase {
    func test_plain_text_becomes_title_with_no_url() async throws {
        let payload = SharePayload.makeStub(items: [.text("Buy milk on the way home")])
        let parsed = try await payload.decode()
        XCTAssertEqual(parsed.suggestedTitle, "Buy milk on the way home")
        XCTAssertNil(parsed.url)
        XCTAssertNil(parsed.notes)
    }

    func test_url_only_yields_link_title_and_attached_url() async throws {
        let url = URL(string: "https://example.com/article")!
        let payload = SharePayload.makeStub(items: [.url(url)])
        let parsed = try await payload.decode()
        XCTAssertEqual(parsed.url, url)
        XCTAssertTrue(parsed.suggestedTitle.contains("example.com"))
    }

    func test_long_text_truncates_title_and_keeps_body_in_notes() async throws {
        let long = String(repeating: "Lorem ipsum ", count: 50)
        let payload = SharePayload.makeStub(items: [.text(long)])
        let parsed = try await payload.decode()
        XCTAssertLessThanOrEqual(parsed.suggestedTitle.count, 80)
        XCTAssertEqual(parsed.notes, long.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func test_text_plus_url_uses_text_as_title_and_attaches_url() async throws {
        let url = URL(string: "https://example.com")!
        let payload = SharePayload.makeStub(items: [
            .text("Read later"),
            .url(url)
        ])
        let parsed = try await payload.decode()
        XCTAssertEqual(parsed.suggestedTitle, "Read later")
        XCTAssertEqual(parsed.url, url)
    }
}
