import Foundation

/// The eleven macOS Settings panes, in sidebar order (issue #62). Single
/// source of truth for the `PreferencesWindow` sidebar rows and the detail
/// switch. Kept dependency-free (no SwiftUI, no pane `View` types) so it
/// co-compiles into the standalone `Lillist-macOSTests` bundle — see
/// `PreferencesPaneTests.swift` and the co-compile entry in `Apps/project.yml`.
enum PreferencesPane: String, CaseIterable, Identifiable, Hashable {
    case iCloudSync, general, tagsAndFilters, notifications, trash, backups
    case quickCapture, reminders, crashReporting, diagnostics, advanced

    var id: String { rawValue }

    /// The English source string and macOS string-catalog key. A plain
    /// `String` (not `LocalizedStringKey`) so it stays assertable by tests;
    /// the view wraps it in `LocalizedStringKey` at the display site.
    var title: String {
        switch self {
        case .iCloudSync: "iCloud Sync"
        case .general: "General"
        case .tagsAndFilters: "Tags & Filters"
        case .notifications: "Notifications"
        case .trash: "Trash"
        case .backups: "Backups"
        case .quickCapture: "Quick Capture"
        case .reminders: "Tasks from Reminders"
        case .crashReporting: "Crash Reporting"
        case .diagnostics: "Diagnostics"
        case .advanced: "Advanced"
        }
    }

    /// SF Symbol name shown alongside the title in the sidebar row.
    var systemImage: String {
        switch self {
        case .iCloudSync: "icloud"
        case .general: "gearshape"
        case .tagsAndFilters: "tag"
        case .notifications: "bell"
        case .trash: "trash"
        case .backups: "archivebox"
        case .quickCapture: "keyboard"
        case .reminders: "tray.and.arrow.down"
        case .crashReporting: "ant"
        case .diagnostics: "stethoscope"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}
