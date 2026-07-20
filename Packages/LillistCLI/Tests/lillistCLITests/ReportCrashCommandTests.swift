import Testing
import Foundation
@testable import lillist_cli
import LillistCore

@Suite("ReportCrashCommand parses + canary handshake")
struct ReportCrashCommandTests {
    @Test("`report-crash` parses with no flags")
    func parses_default() throws {
        let cmd = try ReportCrashCommand.parse([])
        #expect(cmd.noLogs == false)
        #expect(cmd.noBreadcrumbs == false)
    }

    @Test("`report-crash --no-logs --no-breadcrumbs` parses")
    func parses_skipSections() throws {
        let cmd = try ReportCrashCommand.parse(["--no-logs", "--no-breadcrumbs"])
        #expect(cmd.noLogs == true)
        #expect(cmd.noBreadcrumbs == true)
    }

    /// Round-trip the canary-file lifecycle independently of the binary
    /// (the binary writes to ~/Library; tests use temp paths).
    @Test("detectAndPrepare returns a planted stale canary")
    func detect_returnsStale() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-canary-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CanaryFile(url: url)
        // Date(timeIntervalSince1970:) with a whole-second value round-trips
        // through ISO8601 encoding without precision loss.
        let stale = CrashCanary(pid: 99, startedAt: Date(timeIntervalSince1970: 1_500_000), buildVersion: "v", hostname: "h")
        try file.writeFresh(stale)
        let reporter = CrashReporter(
            canaryFile: file,
            buildVersion: "v",
            osVersion: "x",
            deviceModel: "y",
            hostname: "z",
            logFetcher: NoopFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: NoopTransport()
        )
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == stale)
    }

    @Test("No canary present ⇒ detectAndPrepare returns nil and writes a fresh one")
    func detect_armsFreshCanary() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-canary-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CanaryFile(url: url)
        let reporter = CrashReporter(
            canaryFile: file,
            buildVersion: "v",
            osVersion: "x",
            deviceModel: "y",
            hostname: "z",
            logFetcher: NoopFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: NoopTransport()
        )
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == nil)
        // detectAndPrepare also writes a fresh canary for *this* run.
        let fresh = try file.readIfPresent()
        #expect(fresh != nil)
    }
}

private struct NoopFetcher: LogFetching {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] { [] }
}

private actor NoopTransport: CrashReportTransport {
    func send(_ report: CrashReport) async throws {}
}
