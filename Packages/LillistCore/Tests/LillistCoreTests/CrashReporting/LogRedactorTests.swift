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

    @Test("key=value redaction is case-insensitive on the key")
    func keyValue_caseInsensitive() {
        // redact-1: framework/third-party log lines capitalize keys
        // inconsistently. A `Title=` / `NOTES=` / `Tag=` key must redact
        // the same as the lowercase form, or PII leaks on mixed-case input.
        #expect(LogRedactor.redact("Title=Secret") == "Title=<redacted>")
        #expect(LogRedactor.redact("NOTES=Private") == "NOTES=<redacted>")
        #expect(LogRedactor.redact("Tag=Work") == "Tag=<redacted>")
    }

    @Test("iOS container paths redact with lowercase hex and in the App-Group subtree")
    func containerPaths_caseInsensitiveAndAppGroup() {
        // redact-1: the container path pass used an uppercase-only hex
        // class [A-Z0-9-], so a lowercase-UUID Data container leaked its
        // path prefix and the bytes after the UUID; and it only matched
        // the `.../Data/Application/` subtree, not the App-Group
        // `.../Shared/AppGroup/` subtree where the shared store lives.
        let lowerData =
            "/var/mobile/Containers/Data/Application/deadbeef-0000-1111-2222-333344445555/Library/x.png"
        #expect(LogRedactor.redact(lowerData) == "<path>")
        let appGroup =
            "/var/mobile/Containers/Shared/AppGroup/aaaa1111-2222-3333-4444-555566667777/db.sqlite"
        #expect(LogRedactor.redact(appGroup) == "<path>")
    }

    @Test("Temp-directory paths are redacted")
    func tempPaths_redacted() {
        // redact-5: NSTemporaryDirectory / FileManager temp URLs surface
        // in log text (attachment staging, export scratch files) and
        // contain a user-scoped DARWIN_USER_TEMP_DIR token. None of the
        // existing /Users, /var/mobile, or ~ passes match them.
        #expect(
            LogRedactor.redact("saved to /private/var/folders/ab/cd12/T/temp.png") == "saved to <path>"
        )
        #expect(
            LogRedactor.redact("saved to /var/folders/ab/cd12/T/temp.png") == "saved to <path>"
        )
        #expect(LogRedactor.redact("scratch /tmp/scratch.dat") == "scratch <path>")
    }

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
