import SwiftUI
import LillistCore
import LillistUI

struct CrashReportingSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var showSample = false

    var body: some View {
        Section("Crash reporting") {
            Toggle("Show prompt after Lillist quits unexpectedly", isOn: $prefs.crashPromptsEnabled)
            // Only advertise the email destination when a contact address is
            // configured for this build; an unconfigured fork has nowhere to
            // send, so the line is hidden.
            if LillistCoreContact.hasCrashReportRecipient {
                Text("Reports go directly to Mikey via email. No third-party telemetry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if prefs.crashPromptsEnabled {
                DisclosureGroup("View what would be sent", isExpanded: $showSample) {
                    Text(samplePreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: prefs.crashPromptsEnabled) { _, new in
            // Mirror the change into the live env so the current
            // session's CrashReporterHost sees the new value
            // immediately. Plan 9 stores this as `var` for exactly this
            // reason.
            environment.crashPromptsEnabled = new
            // Collapse the preview when prompts are turned off so a
            // later re-enable starts from a closed state — the user
            // shouldn't land in a panel they weren't looking at.
            if !new { showSample = false }
        }
    }

    private var samplePreview: String {
        CrashReportSample.preview(.init(
            buildVersion: environment.buildVersion,
            osVersion: environment.osVersion,
            deviceModel: environment.deviceModel,
            recipient: LillistCoreContact.crashReportRecipient,
            methodSuffix: "Mail (you choose whether to send)."
        ))
    }
}
