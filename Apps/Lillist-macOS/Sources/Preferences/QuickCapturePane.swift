import SwiftUI
import LillistCore

/// macOS Preferences Quick Capture pane (Plan 10 Task 9).
///
/// Two toggles + hotkey text field. The hotkey field is intentionally
/// simple — the canonical hotkey-recording UI lives in Plan 7's hotkey
/// stack (`GlobalHotkeyMonitor`, `QuickCapturePanelController`); this
/// pane writes the textual representation into the `quickCaptureHotkey`
/// preference, and a future iteration can replace the field with a
/// proper key-capture recorder.
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

/// Tiny placeholder hotkey recorder. The real key-capture UI is left
/// for a Plan 7 follow-up; this binds to a string for now so the
/// preference can at least be edited textually.
private struct HotkeyRecorder: View {
    @Binding var value: String
    var body: some View {
        TextField("hotkey", text: $value)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }
}
