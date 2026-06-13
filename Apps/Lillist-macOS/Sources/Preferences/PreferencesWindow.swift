import SwiftUI
import LillistCore
import LillistUI

/// Root of the macOS `Settings { … }` scene. Six tabs match design
/// Section 7. The actual pane implementations land in Task 8 (General)
/// and Task 9 (Notifications / Trash / Quick Capture / Crash Reporting
/// / Advanced).
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
            QuickCapturePane()
                .tabItem { Label("Quick Capture", systemImage: "keyboard") }
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
        // Plan 15 Task 26: pane content drives the window's size
        // (each pane's outer container ends with `.fixedSize()`); the
        // TabView animates between tabs the way System Settings does.
    }
}
