import Foundation

/// Lillist's single source of truth for user-visible contact info.
///
/// Currently scoped to the crash-report recipient — the email address
/// that the macOS `MailtoTransport`, iOS `MailComposerView` host, CLI
/// `CLIMailtoTransport`, and the UI surfaces (the macOS Preferences
/// pane, the iOS Settings section, and the cross-platform
/// `CrashReportSheet`) all consume.
///
/// The address is **not** hardcoded: it is resolved at runtime from the
/// host's build configuration so the public repository ships no personal
/// address. App targets inject it via the `LillistContactEmail`
/// Info.plist key (populated from the `$(LILLIST_CONTACT_EMAIL)` build
/// setting — committed empty in `Apps/Config/Distribution.xcconfig`, with
/// a per-machine override in the gitignored `Signing.local.xcconfig`).
/// The `lillist` CLI, which has no Info.plist key, falls back to the
/// `LILLIST_CONTACT_EMAIL` environment variable. When nothing is
/// configured the recipient is the empty string and callers must treat
/// that as "no contact available" (see `hasCrashReportRecipient`).
public enum LillistCoreContact {
    /// Info.plist key the app targets populate from `$(LILLIST_CONTACT_EMAIL)`.
    public static let infoDictionaryKey = "LillistContactEmail"

    /// Environment-variable fallback for hosts without an Info.plist
    /// contact key — chiefly the `lillist` CLI executable.
    public static let environmentKey = "LILLIST_CONTACT_EMAIL"

    /// Pure resolver: the first non-blank of the Info.plist value then the
    /// environment value, else the empty string. Whitespace-only inputs
    /// are treated as unset. Kept side-effect-free so both branches are
    /// unit-testable without rebuilding the host bundle.
    public static func resolveRecipient(
        infoDictionaryValue: String?,
        environmentValue: String?
    ) -> String {
        for candidate in [infoDictionaryValue, environmentValue] {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    /// Recipient for user-mediated crash reports. Plumbed through
    /// `MailtoTransport.init(recipient:)`,
    /// `CLIMailtoTransport.init(recipient:)`, and the iOS host's
    /// `MailComposerView`. Resolved once from the host bundle /
    /// environment; empty when no contact address is configured for this
    /// build (a fresh fork or a CI build), in which case the crash-report
    /// surfaces hide the recipient-specific affordances.
    public static let crashReportRecipient: String = resolveRecipient(
        infoDictionaryValue: Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
        environmentValue: ProcessInfo.processInfo.environment[environmentKey]
    )

    /// `true` when a contact address is configured for this build.
    public static var hasCrashReportRecipient: Bool {
        !crashReportRecipient.isEmpty
    }
}
