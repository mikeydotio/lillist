import Testing
import Foundation
@testable import LillistCore

@Suite("LogRedactor")
struct LogRedactorTests {
    /// Find a fixture by name relative to this test bundle.
    private func fixture(_ basename: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(
            forResource: basename,
            withExtension: nil,
            subdirectory: "Fixtures"
        ) else {
            Issue.record("Missing fixture \(basename)")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func goldenTest(_ baseName: String) throws {
        let raw = try fixture("\(baseName).txt")
        let expected = try fixture("\(baseName).expected.txt")
        let redacted = LogRedactor.redact(raw)
        #expect(
            redacted == expected,
            "Redaction mismatch for \(baseName).\nGOT:\n\(redacted)\nEXPECTED:\n\(expected)"
        )
    }

    @Test("Strips wrapped titles and title= forms")
    func titles() throws { try goldenTest("raw-logs-with-titles") }

    @Test("Strips user home paths on macOS, iOS, and ~ form")
    func paths() throws { try goldenTest("raw-logs-with-paths") }

    @Test("Replaces UUIDs with <uuid>")
    func uuids() throws { try goldenTest("raw-logs-with-uuids") }

    @Test("Replaces email addresses with <email>")
    func emails() throws { try goldenTest("raw-logs-with-emails") }

    @Test("Strips journal bodies and notes= forms")
    func journalBodies() throws { try goldenTest("raw-logs-with-journal-bodies") }

    @Test("Strips wrapped tag names and tag= forms")
    func tagNames() throws { try goldenTest("raw-logs-with-tag-names") }

    @Test("Empty input → empty output")
    func empty() {
        #expect(LogRedactor.redact("") == "")
    }

    @Test("Plain text with no PII is unchanged")
    func clean() {
        let input = "2026-05-12 10:00:01 [Sync] zone change started"
        #expect(LogRedactor.redact(input) == input)
    }

    @Test("Redaction is idempotent")
    func idempotent() {
        let input = "loaded /Users/mikey/file 12345678-1234-1234-1234-1234567890ab"
        let once = LogRedactor.redact(input)
        let twice = LogRedactor.redact(once)
        #expect(once == twice)
    }
}
