import SwiftUI
import LillistCore
import LillistUI

/// iOS Settings landing screen, surfaced from the navigation-bar gear
/// icon in the root shell. Navigation chrome lives in
/// `LillistUI.SettingsScreen`; this screen presents a list of icon rows
/// that drill into focused sub-pages (`Pages/*.swift`). The env-coupled
/// sections themselves stay co-located with the stores they read; the
/// pages compose them inside `LillistUI.SettingsDetailScreen` chrome.
///
/// Row icon tiles use one fixed `RainbowPalette` functional hue per
/// category as a *wayfinding* signal — color is functional, not
/// decorative (Rainbow Logic house rule).
struct SettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var prefs: PreferencesStore.Prefs?

    var body: some View {
        SettingsScreen(onDone: { dismiss() }) {
            if let b = binding {
                Section {
                    navRow("Appearance", "paintpalette.fill", RainbowPalette.scriptPurple.base) {
                        AppearancePage(prefs: b)
                    }
                    navRow("Task Defaults", "checklist", RainbowPalette.focusBlue.base) {
                        TaskDefaultsPage(prefs: b)
                    }
                    navRow("Notifications", "bell.badge.fill", RainbowPalette.cautionAmber.base) {
                        NotificationsPage(prefs: b)
                    }
                    navRow("iCloud Sync", "icloud.fill", RainbowPalette.Spectrum.cyan) {
                        ICloudSyncPage()
                    }
                    navRow("Quick Capture", "bolt.fill", RainbowPalette.actionOrange.base) {
                        QuickCapturePage(prefs: b)
                    }
                    navRow("Tasks from Reminders", "tray.and.arrow.down.fill", RainbowPalette.Spectrum.lime) {
                        RemindersImportPage()
                    }
                    navRow("Data Management", "externaldrive.fill", RainbowPalette.growthGreen.base) {
                        DataManagementPage(prefs: b)
                    }
                    navRow("Debug", "ladybug.fill", LillistColor.textMuted) {
                        DebugPage(prefs: b)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task { prefs = try? await environment.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await environment.preferencesStore.update { $0 = new } }
        }
    }

    /// A drill-down row: a tinted icon tile + title that pushes a
    /// sub-page within `SettingsScreen`'s navigation stack.
    @ViewBuilder
    private func navRow<Destination: View>(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        _ tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                Text(title)
            } icon: {
                SettingsRowIcon(systemImage: systemImage, tint: tint)
            }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}
