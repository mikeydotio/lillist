import Foundation

/// Orchestrates the full crash-detection-and-report flow per design
/// Section 8: write canary at startup, detect stale canary on next
/// launch, assemble a redacted opt-in payload, and hand it to a
/// transport.
public actor CrashReporter {

    /// The user's choice from the post-crash sheet.
    public enum SubmitDecision: Sendable, Equatable {
        case send
        case dontSend
    }

    private let canaryFile: CanaryFile
    private let buildVersion: String
    private let osVersion: String
    private let deviceModel: String
    private let hostname: String
    private let logFetcher: LogFetching
    private let breadcrumbs: BreadcrumbBuffer
    private let transport: CrashReportTransport
    private let now: @Sendable () -> Date

    /// How recent a same-PID canary's `startedAt` must be to count as a
    /// pre-arm from *this* launch rather than a recycled-PID prior crash.
    /// 30 s comfortably covers app bootstrap + the first foreground
    /// transition while staying far below any realistic inter-launch gap.
    private static let selfWriteWindow: TimeInterval = 30

    public init(
        canaryFile: CanaryFile,
        buildVersion: String,
        osVersion: String,
        deviceModel: String,
        hostname: String,
        logFetcher: LogFetching,
        breadcrumbs: BreadcrumbBuffer,
        transport: CrashReportTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.canaryFile = canaryFile
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.hostname = hostname
        self.logFetcher = logFetcher
        self.breadcrumbs = breadcrumbs
        self.transport = transport
        self.now = now
    }

    /// Write a canary for the current process. Call from lifecycle
    /// entry points (App init / scene willConnect / CLI main).
    public func start() throws {
        let canary = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: now(),
            buildVersion: buildVersion,
            hostname: hostname
        )
        try canaryFile.writeFresh(canary)
    }

    /// Delete the canary. Call from lifecycle exit hooks.
    public func markCleanExit() throws {
        try canaryFile.deleteOnCleanExit()
    }

    /// On launch, return a `CrashCanary` if the previous run did
    /// not exit cleanly. Replaces the canary with a fresh one for
    /// the current run.
    ///
    /// A canary whose `pid` matches the current process *and* whose
    /// `startedAt` is within `selfWriteWindow` of `now()` is a
    /// self-write from earlier in this same launch — possible if a
    /// lifecycle observer (iOS foreground transition) armed the
    /// canary before `detectAndPrepare` ran, or if a caller pre-armed
    /// via `start()`. PID alone is *not* sufficient: the OS recycles
    /// PIDs, so a genuine prior crash can carry the same PID. The
    /// `startedAt` recency check distinguishes a same-launch pre-arm
    /// (recent) from a recycled-PID prior crash (an earlier launch),
    /// so a real crash is never silently swallowed.
    public func detectAndPrepare() throws -> CrashCanary? {
        let prior = try canaryFile.readIfPresent()
        try start()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let prior,
           prior.pid == currentPID,
           abs(prior.startedAt.timeIntervalSince(now())) < Self.selfWriteWindow {
            return nil
        }
        return prior
    }

    /// Submit the user's choice. When `decision == .send`, assembles
    /// a `CrashReport` honoring the section toggles and hands it to
    /// the transport. When `decision == .dontSend`, no transport
    /// invocation happens at all.
    public func submit(
        decision: SubmitDecision,
        description: String?,
        includeLogs: Bool,
        includeBreadcrumbs: Bool,
        pending: CrashCanary
    ) async throws {
        guard decision == .send else { return }

        var logsSection: [String]? = nil
        if includeLogs {
            let rawSince = pending.startedAt.addingTimeInterval(-300)
            let raw = try await logFetcher.fetchRecentLines(
                since: rawSince,
                subsystem: CrashReporting.subsystemIdentifier
            )
            logsSection = raw.map(LogRedactor.redact)
        }

        var breadcrumbsSection: [Breadcrumb]? = nil
        if includeBreadcrumbs {
            breadcrumbsSection = await breadcrumbs.snapshot()
        }

        let report = CrashReport(
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            canary: pending,
            userDescription: description?.isEmpty == true ? nil : description,
            logs: logsSection,
            breadcrumbs: breadcrumbsSection
        )
        try await transport.send(report)
    }
}
