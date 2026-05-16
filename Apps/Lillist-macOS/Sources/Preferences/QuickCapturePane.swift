import SwiftUI
import LillistCore

/// macOS Preferences Quick Capture pane (Plan 10 Task 9).
///
/// Two toggles + the Plan 11 NSEvent-based ``HotkeyRecorder``. The
/// recorder writes its canonical string representation
/// (`"ctrl+opt+space"`, `"cmd+shift+l"`, …) into the
/// `quickCaptureHotkey` preference; `GlobalHotkeyMonitor` reads the
/// same key on next launch.
struct QuickCapturePane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs: PreferencesStore.Prefs?

    var body: some View {
        Form {
            if let b = binding {
                Section("Quick Capture") {
                    Toggle("Enable global Quick Capture", isOn: b.quickCaptureEnabled)
                    Toggle("Show status bar icon", isOn: b.statusBarItemVisible)
                    LabeledContent("Global hotkey") {
                        HotkeyRecorder(value: b.quickCaptureHotkey)
                            .frame(width: 220)
                    }
                }
                Section {
                    Text("Hotkey changes apply on next launch. The recorder accepts strings like `ctrl+opt+space` or `cmd+shift+l`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task { prefs = try? await environment.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await environment.preferencesStore.update { $0 = new } }
            // TODO(Plan 7): re-register the hotkey via
            // GlobalHotkeyMonitor.register(...) so the new combo takes
            // effect without a relaunch. Until then, hotkey edits land
            // in the store but the hotkey monitor still serves the
            // previously-installed combo for the current session.
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}
