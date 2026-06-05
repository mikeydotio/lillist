import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReporter error paths")
struct CrashReporterErrorPathTests {
    /// Sentinel error the throwing fakes raise.
    private struct BoomError: Error, Equatable {}

    /// A transport whose `send` always throws.
    private actor ThrowingTransport: CrashReportTransport {
        private(set) var attempts = 0
        func send(_ report: CrashReport) async throws {
            attempts += 1
            throw BoomError()
        }
    }

    /// A fetcher whose `fetchRecentLines` always throws.
    private struct ThrowingLogFetcher: LogFetching {
        func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] {
            throw BoomError()
        }
    }

    /// Build a reporter with injectable transport + fetcher.
    private func makeReporter(
        logFetcher: LogFetching,
        transport: CrashReportTransport
    ) -> (CrashReporter, URL) {
        let canaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canary-\(UUID()).json")
        let reporter = CrashReporter(
            canaryFile: CanaryFile(url: canaryURL),
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            hostname: "host",
            logFetcher: logFetcher,
            breadcrumbs: BreadcrumbBuffer(),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (reporter, canaryURL)
    }

    @Test("A throwing transport propagates the error out of submit")
    func throwingTransport_propagates() async throws {
        let transport = ThrowingTransport()
        let (reporter, url) = makeReporter(
            logFetcher: FakeLogFetcher(lines: ["line"]),
            transport: transport
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = CrashCanary(
            pid: 1,
            startedAt: Date(timeIntervalSince1970: 999_000),
            buildVersion: "0.9",
            hostname: "old"
        )
        await #expect(throws: BoomError.self) {
            try await reporter.submit(
                decision: .send,
                description: nil,
                includeLogs: false,
                includeBreadcrumbs: false,
                pending: pending
            )
        }
        let attempts = await transport.attempts
        #expect(attempts == 1)
    }

    @Test("A throwing log fetcher propagates and never reaches the transport")
    func throwingFetcher_propagatesBeforeTransport() async throws {
        let transport = ThrowingTransport()
        let (reporter, url) = makeReporter(
            logFetcher: ThrowingLogFetcher(),
            transport: transport
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = CrashCanary(
            pid: 1,
            startedAt: Date(timeIntervalSince1970: 999_000),
            buildVersion: "0.9",
            hostname: "old"
        )
        await #expect(throws: BoomError.self) {
            try await reporter.submit(
                decision: .send,
                description: nil,
                includeLogs: true,             // forces the fetcher path
                includeBreadcrumbs: false,
                pending: pending
            )
        }
        // The fetcher threw first, so the transport must never be called.
        let attempts = await transport.attempts
        #expect(attempts == 0)
    }

    @Test("dontSend never touches a throwing transport")
    func dontSend_skipsThrowingTransport() async throws {
        let transport = ThrowingTransport()
        let (reporter, url) = makeReporter(
            logFetcher: FakeLogFetcher(lines: ["line"]),
            transport: transport
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = CrashCanary(
            pid: 1,
            startedAt: Date(timeIntervalSince1970: 999_000),
            buildVersion: "0.9",
            hostname: "old"
        )
        try await reporter.submit(
            decision: .dontSend,
            description: nil,
            includeLogs: true,
            includeBreadcrumbs: true,
            pending: pending
        )
        let attempts = await transport.attempts
        #expect(attempts == 0)
    }
}
