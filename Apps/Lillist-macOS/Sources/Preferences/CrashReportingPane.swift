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
                    // Only advertise the email destination when a contact
                    // address is configured for this build; an unconfigured
                    // fork has nowhere to send, so the line is hidden.
                    if LillistCoreContact.hasCrashReportRecipient {
                        Text("Reports go directly to Mikey via email. No third-party telemetry.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    DisclosureGroup("View what would be sent", isExpanded: $sampleVisible) {
                        // The preview shows the build/OS/device/recipient
                        // header only. Breadcrumbs and crashed-run logs are
                        // not captured post-crash today (BreadcrumbBuffer is
                        // in-memory; OSLogFetcher scopes to the current
                        // process), so the preview must not advertise them.
                        // A real on-disk buffer is owned by the
                        // observability-logging plan; when it lands, restore
                        // the breadcrumbs/logs preview sections together with
                        // the live render.
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
        .task { await subscribe() }
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

    private func subscribe() async {
        if prefs == nil {
            prefs = try? await environment.preferencesStore.read()
        }
        for await snapshot in environment.preferencesStore.prefsStream {
            if snapshot != prefs {
                prefs = snapshot
            }
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
            recipient: LillistCoreContact.crashReportRecipient,
            methodSuffix: "macOS Mail.app draft via mailto: — you choose whether to send."
        ))
    }
}
