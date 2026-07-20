import Foundation
import LillistCore

/// Static-lifetime hook bag used by `main.swift` to arm the canary at
/// startup, surface the "previous run crashed" notice on TTY, and
/// delete the canary on clean exit. Lives in `Support/` so unit tests
/// don't need to exercise the main.swift entry point directly.
public enum CLICanaryLifecycle {
    /// Build a fresh `CrashReporter` with platform-correct defaults.
    /// Production callers pass the default constructor; tests inject
    /// fakes via `LillistCore.CrashReporter.init(...)` directly.
    public static func makeReporter() -> CrashReporter {
        CrashReporter(
            canaryFile: CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI)),
            buildVersion: LillistCoreInfo.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Host.current().localizedName ?? "Mac",
            hostname: Host.current().localizedName ?? "Mac",
            logFetcher: OSLogFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: CLIMailtoTransport()
        )
    }

    /// On startup: write a fresh canary, and — if a stale canary from a
    /// prior crashed run is present and we're on a TTY — print a notice
    /// to stderr telling the user how to send a report. Returns the
    /// stale canary (if any) so a higher-level caller can record it.
    @discardableResult
    public static func bootstrap(reporter: CrashReporter) async -> CrashCanary? {
        let staleBefore = try? CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI)).readIfPresent()
        try? await reporter.start()
        if staleBefore != nil, isatty(fileno(stdout)) != 0 {
            FileHandle.standardError.write(Data(
                "lillist: previous run did not exit cleanly. Run `lillist report-crash` to send a report.\n".utf8
            ))
        }
        return staleBefore
    }

    /// On clean exit: delete the canary so the next launch knows this
    /// run terminated normally. Block briefly but never hang.
    public static func teardown(reporter: CrashReporter) {
        let group = DispatchGroup()
        group.enter()
        Task {
            try? await reporter.markCleanExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + .seconds(1))
    }

    /// Signal-handler-safe synchronous canary delete. Cannot touch any
    /// async context from a POSIX signal handler.
    public static func teardownSync() {
        try? CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI)).deleteOnCleanExit()
    }
}
