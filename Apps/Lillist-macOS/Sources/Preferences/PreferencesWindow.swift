import SwiftUI
import LillistCore
import LillistUI

/// Root of the macOS `Settings { … }` scene. Eleven panes (design
/// Section 7): iCloud Sync, General, Tags & Filters, Notifications, Trash,
/// Backups, Quick Capture, Tasks from Reminders, Crash Reporting, Diagnostics,
/// Advanced — enumerated by `PreferencesPane` and rendered as a source-list
/// sidebar (issue #62). The old top-toolbar `TabView` overflowed once panes
/// exceeded the toolbar's width, collapsing extras behind a grayed-out `>>`
/// chevron menu; a sidebar has no such ceiling — it scrolls instead — and,
/// paired with `.windowResizability(.contentMinSize)` on the `Settings`
/// scene (`LillistApp.swift`), the window is now freely resizable.
struct PreferencesWindow: View {
    @State private var selection: PreferencesPane? = .iCloudSync

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(PreferencesPane.allCases) { pane in
                    Label {
                        Text(LocalizedStringKey(pane.title))
                    } icon: {
                        Image(systemName: pane.systemImage)
                    }
                    .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(
                min: PreferencesMetrics.sidebarMinWidth,
                ideal: PreferencesMetrics.sidebarIdealWidth,
                max: PreferencesMetrics.sidebarMaxWidth
            )
        } detail: {
            let current = selection ?? .iCloudSync
            detail(for: current)
                .frame(
                    minWidth: PreferencesMetrics.detailMinWidth,
                    idealWidth: PreferencesMetrics.detailIdealWidth,
                    maxWidth: .infinity,
                    minHeight: PreferencesMetrics.detailMinHeight,
                    maxHeight: .infinity
                )
                .navigationTitle(Text(LocalizedStringKey(current.title)))
        }
        // Rainbow Logic full-whimsy: every pane toggle uses the tactile
        // switch. Window chrome, sidebar, and Form layout stay native.
        .toggleStyle(.rainbow)
    }

    @ViewBuilder
    private func detail(for pane: PreferencesPane) -> some View {
        switch pane {
        case .iCloudSync: ICloudSyncPane()
        case .general: GeneralPane()
        case .tagsAndFilters: TagsAndFiltersPane()
        case .notifications: NotificationsPane()
        case .trash: TrashPane()
        case .backups: BackupPane()
        case .quickCapture: QuickCapturePane()
        case .reminders: RemindersPane()
        case .crashReporting: CrashReportingPane()
        case .diagnostics: DiagnosticsPane()
        case .advanced: AdvancedPane()
        }
    }
}

/// Sizing for the macOS Settings sidebar + detail column (issue #62).
/// Replaces the old single pinned `contentWidth`: every pane used to pin
/// 520pt + `.fixedSize()` so the toolbar-tab row wouldn't reflow — obsolete
/// now that panes live in a resizable `NavigationSplitView` detail column.
enum PreferencesMetrics {
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 215
    static let sidebarMaxWidth: CGFloat = 260
    static let detailMinWidth: CGFloat = 480
    static let detailIdealWidth: CGFloat = 520
    static let detailMinHeight: CGFloat = 400
}
