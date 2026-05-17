import SwiftUI
import LillistCore
import LillistUI

/// macOS Preferences Crash Reporting pane (Plan 10 Task 9).
///
/// Single toggle bound to `crashPromptsEnabled` (Plan 9). A disclosure
/// group surfaces a sample preview of what a crash report would look
/// like — this is the Plan-9-promised affordance to let curious users
/// inspect the payload before deciding whether to keep prompts on.
struct CrashReportingPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs: PreferencesStore.Prefs?
    @State private var sampleVisible = false

    var body: some View {
        Form {
            if let b = binding {
                Section("Post-crash prompt") {
                    Toggle("Show prompt after Lillist quits unexpectedly", isOn: b.crashPromptsEnabled)
                    Text("Reports go directly to Mikey via email. No third-party telemetry.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("View what would be sent", isExpanded: $sampleVisible) {
                        // TODO(Plan 19 / Plan 14 follow-up): swap to a live
                        // CrashReporter.preview() once that method lands. The
                        // current text is the static `CrashReportSample.preview`
                        // template (placeholder strings for breadcrumbs and
                        // logs); a live render would invoke the BreadcrumbBuffer
                        // and LogFetching to show the actual payload that would
                        // be sent. Plan 14 shipped CrashReportSample.preview but
                        // not the reporter-driven live renderer.
                        Text(samplePreview)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .fixedSize() // Plan 15 Task 26: pane self-sizes; window animates
        .task { prefs = try? await environment.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await environment.preferencesStore.update { $0 = new } }
            // Plan 9 wires `crashPromptsEnabled` through to the live
            // CrashReporterHost via `AppEnvironment.crashPromptsEnabled`
            // (a `var`). Mirror the change so the current launch picks
            // up the new value if the user toggles mid-session.
            environment.crashPromptsEnabled = new.crashPromptsEnabled
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private var samplePreview: String {
        CrashReportSample.preview(.init(
            buildVersion: environment.buildVersion,
            osVersion: environment.osVersion,
            deviceModel: environment.deviceModel,
            recipient: "mikeyward@gmail.com",
            methodSuffix: "macOS Mail.app draft via mailto: — you choose whether to send."
        ))
    }
}
