import SwiftUI
import LillistCore
import LillistUI

/// macOS Preferences Crash Reporting pane (Plan 10 Task 9).
///
/// Single toggle bound to `crashPromptsEnabled` (Plan 9). A disclosure
/// group surfaces a sample preview of what a crash report would look
/// like — this is the Plan-9-promised affordance to let curious users
/// inspect the payload before deciding whether to keep prompts on.
///
/// LIL-77: the crash-prompt opt-in is Plan-21 device-local state
/// (`DevicePreferencesStore`), not part of the shared, CloudKit-synced
/// `Prefs` — mirrors `DiagnosticsPane`'s write-through-`Binding` hydration
/// pattern (`.task` hydrates without writing; only a user tap routes
/// through `set` to persist). The prior implementation bound this toggle
/// to `PreferencesStore.Prefs.crashPromptsEnabled` and persisted the WHOLE
/// `Prefs` struct via `environment.preferencesStore.update` — a real
/// write, but to the wrong store: `AppEnvironment.crashPromptsEnabled`
/// (what `CrashReporterHost` actually reads at boot) initializes from
/// `DevicePreferencesStore`, which this toggle never touched. A user's
/// choice could silently revert on the next relaunch.
struct CrashReportingPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var enabled = PreferencesStore.Prefs.crashPromptsDefault
    @State private var didHydrate = false
    @State private var sampleVisible = false

    var body: some View {
        Form {
            Section("Post-crash prompt") {
                Toggle("Show prompt after Lillist quits unexpectedly", isOn: enabledBinding)
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
        }
        .formStyle(.grouped)
        .task {
            let initial = await environment.devicePreferences.crashPromptsEnabled()
            if !didHydrate { enabled = initial; didHydrate = true }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                didHydrate = true   // user is authoritative now — .task must not overwrite
                enabled = newValue
                // Plan 9 wires `crashPromptsEnabled` through to the live
                // CrashReporterHost via `AppEnvironment.crashPromptsEnabled`
                // (a `var`). Mirror the change so the current launch picks
                // up the new value if the user toggles mid-session.
                environment.crashPromptsEnabled = newValue
                Task { await environment.devicePreferences.setCrashPromptsEnabled(newValue) }
            }
        )
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
