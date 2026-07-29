import SwiftUI
import LillistCore
import LillistUI

/// LIL-77: the crash-prompt opt-in is Plan-21 device-local state
/// (`DevicePreferencesStore`), not part of the shared, CloudKit-synced
/// `Prefs` — mirrors `DiagnosticsSection`'s write-through-`Binding`
/// hydration pattern (`.task` hydrates without writing; only a user tap
/// routes through `set` to persist). The prior implementation bound this
/// toggle to `PreferencesStore.Prefs.crashPromptsEnabled` and persisted via
/// `SettingsTab`'s shared `preferencesStore.update` — a real write, but to
/// the wrong store: `AppEnvironment.crashPromptsEnabled` (what
/// `CrashReporterHost` actually reads at boot) initializes from
/// `DevicePreferencesStore`, which this toggle never touched. A user's
/// choice could silently revert on the next relaunch.
struct CrashReportingSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var enabled = PreferencesStore.Prefs.crashPromptsDefault
    @State private var didHydrate = false
    @State private var showSample = false

    var body: some View {
        Section("Crash reporting") {
            Toggle("Show prompt after Lillist quits unexpectedly", isOn: enabledBinding)
            // Only advertise the email destination when a contact address is
            // configured for this build; an unconfigured fork has nowhere to
            // send, so the line is hidden.
            if LillistCoreContact.hasCrashReportRecipient {
                Text("Reports go directly to Mikey via email. No third-party telemetry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if enabled {
                DisclosureGroup("View what would be sent", isExpanded: $showSample) {
                    Text(samplePreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
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
                // Mirror the change into the live env so the current
                // session's CrashReporterHost sees the new value
                // immediately. Plan 9 stores this as `var` for exactly this
                // reason.
                environment.crashPromptsEnabled = newValue
                Task { await environment.devicePreferences.setCrashPromptsEnabled(newValue) }
                // Collapse the preview when prompts are turned off so a
                // later re-enable starts from a closed state — the user
                // shouldn't land in a panel they weren't looking at.
                if !newValue { showSample = false }
            }
        )
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
