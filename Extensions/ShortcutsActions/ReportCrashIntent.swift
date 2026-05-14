import AppIntents
import Foundation
import LillistCore

/// Lightweight Shortcut action that surfaces "is there a pending
/// crash to report?" — without doing the actual reporting (which
/// needs the host app's UI for the post-crash sheet and mail
/// composer). When invoked from outside the host app, it opens
/// Lillist so the next launch's `CrashReporterHost` can present
/// the report sheet against the same canary.
public struct ReportCrashIntent: AppIntent {
    public static let title: LocalizedStringResource = "Report a Lillist crash"
    public static let description = IntentDescription("Sends a redacted crash report via Mail if Lillist quit unexpectedly.")
    public static let openAppWhenRun: Bool = true
    public static let isDiscoverable: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let url = CanaryFile.defaultURL(for: .iOSApp)
        return .result(value: ReportCrashIntentResolver.resolve(canaryURL: url))
    }
}

/// Pure-Swift helper extracted from `ReportCrashIntent.perform()` so
/// unit tests can exercise it without instantiating an `AppIntent`
/// type or touching the real `~/Library` / App Group paths.
public enum ReportCrashIntentResolver {
    public static func resolve(canaryURL: URL) -> String {
        let file = CanaryFile(url: canaryURL)
        if (try? file.readIfPresent()) == nil {
            return "No pending crash to report."
        }
        return "Open Lillist to complete the crash report."
    }
}
