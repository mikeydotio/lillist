import SwiftUI
import LillistCore

struct QuickCaptureSection: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        Section("Quick Capture") {
            Toggle("Show floating + button", isOn: $prefs.quickCaptureEnabled)
            if let url = URL(string: "shortcuts://") {
                Link("Open Shortcuts app", destination: url)
            }
            Text("On iOS, Quick Capture lives in the Shortcuts app and the share sheet. Open Shortcuts to set up a Lock Screen action for one-tap capture.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
