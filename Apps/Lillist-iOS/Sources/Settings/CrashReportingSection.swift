import SwiftUI
import LillistCore

struct CrashReportingSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var showSample = false

    var body: some View {
        Section("Crash reporting") {
            Toggle("Show prompt after Lillist quits unexpectedly", isOn: $prefs.crashPromptsEnabled)
            Text("Reports go directly to Mikey via email. No third-party telemetry.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            DisclosureGroup("View what would be sent", isExpanded: $showSample) {
                Text(samplePreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .onChange(of: prefs.crashPromptsEnabled) { _, new in
            // Mirror the change into the live env so the current
            // session's CrashReporterHost sees the new value
            // immediately. Plan 9 stores this as `var` for exactly this
            // reason.
            environment.crashPromptsEnabled = new
        }
    }

    private var samplePreview: String {
        """
        Build: \(environment.buildVersion)
        OS: \(environment.osVersion)
        Device: \(environment.deviceModel)
        Breadcrumbs:
          (Anonymized verbs from your last ~50 mutations.)
        Logs:
          (System logs from the last ~30 seconds of the crashed run.)
        Sent via: Mail (you choose whether to send).
        """
    }
}
