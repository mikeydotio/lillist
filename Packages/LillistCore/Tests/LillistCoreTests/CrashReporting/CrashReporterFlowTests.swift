import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReporter flow")
struct CrashReporterFlowTests {
    /// Make a reporter writing to a sandboxed canary URL.
    /// Synchronously primes the buffer so tests don't race a fire-and-forget Task.
    private func makeReporter(
        logs: [String] = ["redacted log line"],
        breadcrumbs: [Breadcrumb] = [Breadcrumb(action: "task.create", at: .now, success: true)],
        transport: CrashReportTransport
    ) async -> (CrashReporter, URL) {
        let canaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canary-\(UUID()).json")
        let buffer = BreadcrumbBuffer()
        for crumb in breadcrumbs {
            try? await buffer.record(action: crumb.action, success: crumb.success, at: crumb.at)
        }
        let reporter = CrashReporter(
            canaryFile: CanaryFile(url: canaryURL),
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            hostname: "host",
            logFetcher: FakeLogFetcher(lines: logs),
            breadcrumbs: buffer,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (reporter, canaryURL)
    }

    @Test("No canary on launch ⇒ no pending crash")
    func noCanary_noPendingCrash() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == nil)
    }

    @Test("Stale canary on launch ⇒ pending crash returned, then fresh canary written")
    func staleCanary_returnsPending() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        // Plant a stale canary as if a prior run crashed.
        let stale = CrashCanary(pid: 99, startedAt: Date(timeIntervalSince1970: 999_000), buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == stale)
        // A fresh canary is now in place for *this* run.
        let fresh = try CanaryFile(url: url).readIfPresent()
        #expect(fresh != nil)
        #expect(fresh != stale)
    }

    @Test("Self-pid canary on launch ⇒ no pending crash (a pre-armed canary isn't a crash)")
    func selfPidCanary_isNotPending() async throws {
        // Regression: bootstrap and lifecycle observers can pre-arm
        // the canary before `detectAndPrepare` runs; that write must
        // not be surfaced as a "prior crash."
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let selfCanary = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            // Recent startedAt (matches the reporter's pinned now of
            // 1_000_000) so it reads as a same-launch pre-arm, not a
            // recycled-PID prior crash. See canary-4.
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            buildVersion: "1.0 (1)",
            hostname: "host"
        )
        try CanaryFile(url: url).writeFresh(selfCanary)
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == nil)
    }

    @Test("Recycled-PID prior crash with an old startedAt IS surfaced")
    func recycledPidOldStart_isPending() async throws {
        // canary-4: the OS recycles PIDs. A real prior crash can carry the
        // same PID as this process. Suppressing purely on PID equality
        // would silently swallow that crash. The prior canary's startedAt
        // is from an *earlier* launch, so it is far from this run's now().
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        // reporter "now" is 1_000_000; plant a same-PID canary that started
        // a full hour earlier — unmistakably a prior launch.
        let recycled = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(timeIntervalSince1970: 1_000_000 - 3600),
            buildVersion: "0.9",
            hostname: "old"
        )
        try CanaryFile(url: url).writeFresh(recycled)
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == recycled)
    }

    @Test("Self-pre-armed canary with a recent startedAt is NOT surfaced")
    func selfPidRecentStart_isNotPending() async throws {
        // canary-4: a pre-arm earlier in *this* launch has startedAt ≈ now,
        // so it must still be filtered out even though PIDs can recycle.
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let selfRecent = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(timeIntervalSince1970: 1_000_000 - 1), // 1s ago
            buildVersion: "1.0 (1)",
            hostname: "host"
        )
        try CanaryFile(url: url).writeFresh(selfRecent)
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == nil)
    }

    @Test("Don't-send: transport is not invoked")
    func dontSend_noTransport() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .dontSend,
            description: nil,
            includeLogs: false,
            includeBreadcrumbs: false,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.isEmpty)
    }

    @Test("Send with both sections: payload includes logs and breadcrumbs")
    func send_bothSections() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .send,
            description: "what I was doing",
            includeLogs: true,
            includeBreadcrumbs: true,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.count == 1)
        #expect(captured.first?.logs?.isEmpty == false)
        #expect(captured.first?.breadcrumbs?.isEmpty == false)
        #expect(captured.first?.userDescription == "what I was doing")
    }

    @Test("Send with neither section: payload omits logs and breadcrumbs")
    func send_neitherSection() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .send,
            description: nil,
            includeLogs: false,
            includeBreadcrumbs: false,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.count == 1)
        #expect(captured.first?.logs == nil)
        #expect(captured.first?.breadcrumbs == nil)
    }

    @Test("Logs are redacted before assembly")
    func send_logsAreRedacted() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(
            logs: ["loaded task 12345678-1234-1234-1234-1234567890ab"],
            transport: recording
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .send,
            description: nil,
            includeLogs: true,
            includeBreadcrumbs: false,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.first?.logs?.first?.contains("<uuid>") == true)
        #expect(captured.first?.logs?.first?.contains("12345678") == false)
    }

    @Test("markCleanExit removes the canary")
    func cleanExit_deletesCanary() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        try await reporter.start()
        #expect(FileManager.default.fileExists(atPath: url.path))
        try await reporter.markCleanExit()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
