import Foundation

/// Lillist's single source of truth for user-visible contact info.
///
/// Currently scoped to the crash-report recipient — the email address
/// that the macOS `MailtoTransport`, iOS `MailComposerView` host, CLI
/// `CLIMailtoTransport`, and the UI surfaces (the macOS Preferences
/// pane, the iOS Settings section, and the cross-platform
/// `CrashReportSheet`) all consume.
///
/// Adding a second piece of contact info (a support URL, a forum link)
/// goes here too. Keep the surface minimal — this is `static let`
/// constants, not configuration.
public enum LillistCoreContact {
    /// Recipient for user-mediated crash reports. Plumbed through
    /// `MailtoTransport.init(recipient:)`,
    /// `CLIMailtoTransport.init(recipient:)`, and the iOS host's
    /// `MailComposerView`. Six prior copies of this string lived in
    /// app-target Preferences UI strings and transport defaults;
    /// Plan 19 Task 13 collapsed those into this single declaration.
    public static let crashReportRecipient: String = "mikeyward@gmail.com"
}
