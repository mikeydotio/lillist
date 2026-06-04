import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.Config")
struct ConfigTests {
    private func writeToml(_ contents: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lillist-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.toml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("All three keys parse")
    func allKeys() throws {
        let url = try writeToml("""
        output_format = "json"
        sort = "deadline"
        time_zone = "America/Los_Angeles"
        """)
        let cfg = try CLIBridge.Config.read(from: url)
        #expect(cfg.outputFormat == .json)
        #expect(cfg.sort == .deadline)
        #expect(cfg.timeZone?.identifier == "America/Los_Angeles")
    }

    @Test("Missing file returns defaults")
    func missingFile() throws {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).toml")
        let cfg = try CLIBridge.Config.read(from: url)
        #expect(cfg.outputFormat == .pretty)
        #expect(cfg.sort == .manualPosition)
    }

    @Test("Comments and blank lines tolerated")
    func commentsAndBlanks() throws {
        let url = try writeToml("""
        # this is a comment
        output_format = "ndjson"

        # another
        sort = "title"
        """)
        let cfg = try CLIBridge.Config.read(from: url)
        #expect(cfg.outputFormat == .ndjson)
        #expect(cfg.sort == .title)
    }

    @Test("Single-quoted strings parse")
    func singleQuoted() throws {
        let url = try writeToml("output_format = 'tsv'")
        let cfg = try CLIBridge.Config.read(from: url)
        #expect(cfg.outputFormat == .tsv)
    }

    @Test("Invalid output_format throws validationFailed")
    func invalidOutput() throws {
        let url = try writeToml("output_format = \"yaml\"")
        #expect(throws: LillistError.self) {
            _ = try CLIBridge.Config.read(from: url)
        }
    }

    @Test("Default location is ~/.config/lillist/config.toml")
    func defaultLocation() {
        let url = CLIBridge.Config.defaultLocation()
        #expect(url.path.hasSuffix(".config/lillist/config.toml"))
    }

    @Test("resolvedCalendar uses the configured time zone")
    func resolvedCalendarUsesConfiguredZone() throws {
        let url = try writeToml("time_zone = \"America/Los_Angeles\"")
        let cfg = try CLIBridge.Config.read(from: url)
        let cal = cfg.resolvedCalendar()
        #expect(cal.timeZone.identifier == "America/Los_Angeles")
    }

    @Test("resolvedCalendar falls back to current when no time zone is set")
    func resolvedCalendarDefaultsToCurrent() throws {
        let cfg = CLIBridge.Config()
        let cal = cfg.resolvedCalendar()
        #expect(cal.timeZone == Calendar.current.timeZone)
    }

    @Test("Invalid time_zone throws validationFailed")
    func invalidTimeZone() throws {
        let url = try writeToml("time_zone = \"Mars/Olympus_Mons\"")
        #expect(throws: LillistError.self) {
            _ = try CLIBridge.Config.read(from: url)
        }
    }
}
