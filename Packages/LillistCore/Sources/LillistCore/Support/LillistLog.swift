import Foundation
import os

/// Central `os.Logger` taxonomy for Lillist's production diagnostics.
///
/// ## Why the subsystem is pinned to the crash reporter's
///
/// The crash report's "Recent app logs" section is assembled by
/// `CrashReporter.submit(includeLogs:)`, which calls
/// `OSLogFetcher.fetchRecentLines(since:subsystem:)` with
/// `CrashReporting.subsystemIdentifier` and **discards every unified-log
/// entry whose `subsystem` differs** (`OSLogFetcher.swift`). So the only
/// way that section is ever non-empty is for production loggers to write
/// on that exact subsystem. Pinning `LillistLog.subsystem` to
/// `CrashReporting.subsystemIdentifier` is therefore the load-bearing
/// wiring that makes the shipped logs toggle honest — do not split it.
///
/// Categories are a Console.app filtering convenience only; they do not
/// affect which lines the crash reporter collects (it filters on
/// subsystem, not category).
///
/// ## Privacy
///
/// Every collected line passes through `LogRedactor.redact` before it
/// leaves the device. Treat that as defense-in-depth, not a license to
/// log content: log verbs, counts, durations, and enum raw values, never
/// titles / notes / journal bodies / paths. Use `.public` interpolation
/// only for already-non-identifying values (counts, mode names, error
/// type descriptions).
public enum LillistLog {
    /// The single unified-log subsystem for all Lillist diagnostics.
    /// Pinned to the crash reporter's subsystem on purpose (see above).
    public static let subsystem = CrashReporting.subsystemIdentifier

    /// CloudKit sync + migration state machine.
    public static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Core Data stores (heavy fetches, batch work, save failures).
    public static let store = Logger(subsystem: subsystem, category: "store")

    /// Spotlight indexing (macOS).
    public static let indexing = Logger(subsystem: subsystem, category: "indexing")

    /// App-shell / service-provider lifecycle and failures.
    public static let app = Logger(subsystem: subsystem, category: "app")

    /// MetricKit crash/hang/launch payloads (iOS).
    public static let metrics = Logger(subsystem: subsystem, category: "metrics")

    /// Shared signposter for `OSSignposter` intervals around the
    /// migration runner and heavy fetch paths. Built from a `Logger`
    /// so it is enabled in normal builds (the `.disabled` singleton is
    /// the no-op variant).
    public static let signposter = OSSignposter(
        logger: Logger(subsystem: subsystem, category: "signpost")
    )
}
