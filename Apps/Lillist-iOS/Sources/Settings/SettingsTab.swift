import SwiftUI
import LillistCore

/// iOS Settings screen surfaced from the navigation-bar gear icon in
/// the root shell. Same content matrix as the macOS Preferences scene,
/// adapted to iOS Form/Section conventions.
struct SettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var prefs: PreferencesStore.Prefs?

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { prefs = try? await environment.preferencesStore.read() }
            .onChange(of: prefs) { _, new in
                guard let new else { return }
                Task { try? await environment.preferencesStore.update { $0 = new } }
            }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}
