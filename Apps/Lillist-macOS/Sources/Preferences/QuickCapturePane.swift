import SwiftUI
import LillistCore

/// macOS Preferences Quick Capture pane (Plan 10 Task 9).
///
/// Two toggles + the Plan 11 NSEvent-based ``HotkeyRecorder``. The
/// recorder writes its canonical string representation
/// (`"ctrl+opt+space"`, `"cmd+shift+l"`, …) into the
/// `quickCaptureHotkey` preference. Plan 11 Task 18 makes the change
/// take effect immediately by calling
/// ``GlobalHotkeyMonitor/reregister(combo:)`` after the store update
/// lands.
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
                    Text("Press Record, then your key combination. Changes apply immediately.")
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
            let monitor = environment.hotkeyMonitor
            Task {
                try? await environment.preferencesStore.update { $0 = new }
                // Plan 11 Task 18: re-arm the global hotkey with the
                // newly-saved combo so the change takes effect without
                // a relaunch. `reregister` is idempotent and tolerates
                // unparseable strings (it ignores them).
                monitor.reregister(combo: new.quickCaptureHotkey)
            }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}
