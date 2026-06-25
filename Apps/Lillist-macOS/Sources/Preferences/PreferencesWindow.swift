import SwiftUI
import LillistCore
import LillistUI

/// Root of the macOS `Settings { … }` scene. Ten panes (design
/// Section 7): iCloud Sync, General, Notifications, Trash, Backups, Quick
/// Capture, Tasks from Reminders, Crash Reporting, Diagnostics, Advanced. Each
/// pane self-sizes its height but pins a common
/// `PreferencesMetrics.contentWidth` so the window — and the toolbar tab row —
/// stay put when switching panes.
struct PreferencesWindow: View {
    var body: some View {
        TabView {
            ICloudSyncPane()
                .tabItem { Label("iCloud Sync", systemImage: "icloud") }
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationsPane()
                .tabItem { Label("Notifications", systemImage: "bell") }
            TrashPane()
                .tabItem { Label("Trash", systemImage: "trash") }
            BackupPane()
                .tabItem { Label("Backups", systemImage: "archivebox") }
            QuickCapturePane()
                .tabItem { Label("Quick Capture", systemImage: "keyboard") }
            RemindersPane()
                .tabItem { Label("Tasks from Reminders", systemImage: "tray.and.arrow.down") }
            CrashReportingPane()
                .tabItem { Label("Crash Reporting", systemImage: "ant") }
            DiagnosticsPane()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            AdvancedPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        // Rainbow Logic full-whimsy: every pane toggle uses the tactile
        // switch. Window chrome, tab bar, and Form layout stay native.
        .toggleStyle(.rainbow)
        // Plan 15 Task 26: each pane self-sizes its *height* (its outer
        // container ends with `.fixedSize()`); the TabView animates the
        // height between tabs the way System Settings does. Width is pinned
        // to `PreferencesMetrics.contentWidth` across every pane so the
        // window — and the toolbar tab row — don't reflow on tab switch.
    }
}

/// Shared metrics for the macOS Preferences panes. A single pinned content
/// width keeps the Settings window from resizing (and the toolbar tabs from
/// shifting) every time the user switches panes — see the 2026-06-23 macOS
/// visual design pass (docs/reviews/).
enum PreferencesMetrics {
    static let contentWidth: CGFloat = 520
}
