import SwiftUI
import LillistCore
import LillistUI

/// iOS Settings screen surfaced from the navigation-bar gear icon in
/// the root shell. Plan 20a Task 4e: navigation chrome lives in
/// `LillistUI.SettingsScreen`; the env-coupled sections stay here so
/// they keep their direct access to `AppEnvironment` (stores,
/// schedulers, build/os/device strings).
struct SettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var prefs: PreferencesStore.Prefs?

    var body: some View {
        SettingsScreen(onDone: { dismiss() }) {
            if let b = binding {
                GeneralSection(prefs: b)
                NotificationsSection(prefs: b)
                TrashSection(prefs: b)
                QuickCaptureSection(prefs: b)
                CrashReportingSection(prefs: b)
                AdvancedSection()
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

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}
