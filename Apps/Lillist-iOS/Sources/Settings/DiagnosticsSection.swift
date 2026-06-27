import SwiftUI
import UniformTypeIdentifiers
import LillistCore
import LillistUI

/// Owns the Diagnostics export state + pipeline. Lifted out of
/// `DiagnosticsSection` so the include `.sheet` and `.fileExporter` can be
/// hosted by the **page** (`DebugPage`) on the `SettingsDetailScreen` container
/// rather than on a `Section`. A `.sheet` attached to `Section`/Form-row content
/// inside a pushed `NavigationStack` destination (itself inside the Settings
/// `.sheet`) presents-then-immediately-dismisses and tears the whole Settings
/// sheet down with it — see `docs/engineering-notes.md`. Hosting the
/// presentation on the stable Form container is the fix.
@MainActor
@Observable
final class DiagnosticsExportModel {
    var enabled = false
    var showInclude = false
    var includeLogs = true
    var includeStore = true
    var isPreparing = false
    var exportDocument: DiagnosticZipDocument?
    var showExporter = false
    var lastError: String?

    private var didHydrate = false
    private var wantsExport = false

    /// One-shot hydration: if the user already toggled while this read was in
    /// flight, `didHydrate` is already true and the stale read is dropped.
    func hydrate(_ env: AppEnvironment) async {
        let initial = await env.devicePreferences.diagnosticLoggingEnabled()
        if !didHydrate { enabled = initial; didHydrate = true }
    }

    func setLogging(_ on: Bool, _ env: AppEnvironment) {
        didHydrate = true   // user is authoritative now — hydrate must not overwrite
        enabled = on
        Task {
            await env.devicePreferences.setDiagnosticLoggingEnabled(on)
            await env.diagnosticLog.setEnabled(on)
        }
    }

    /// Tapped "Create" in the include sheet: remember the intent and dismiss the
    /// sheet; the actual build runs in `includeSheetDismissed` so the exporter
    /// only presents after the include sheet has fully gone.
    func requestCreate() { wantsExport = true; showInclude = false }

    func includeSheetDismissed(_ env: AppEnvironment) {
        if wantsExport { wantsExport = false; Task { await prepare(env) } }
    }

    private func prepare(_ env: AppEnvironment) async {
        isPreparing = true
        lastError = nil
        defer { isPreparing = false }
        let metadata = DiagnosticPackageBuilder.Metadata(
            buildVersion: env.buildVersion,
            osVersion: env.osVersion,
            deviceModel: env.deviceModel,
            exportedAt: Date(),
            diagnosticLoggingEnabled: enabled
        )
        let builder = DiagnosticPackageBuilder(
            diagnosticsDir: await env.diagnosticLog.diagnosticsDirectory(),
            storeURL: env.storeURL,
            metadata: metadata
        )
        do {
            let zipURL = try await builder.build(options: .init(includeLogs: includeLogs, includeStore: includeStore))
            exportDocument = try DiagnosticZipDocument(url: zipURL)
            try? FileManager.default.removeItem(at: zipURL)   // the document holds the bytes now
            showExporter = true
        } catch {
            lastError = "Couldn't build diagnostic package: \(error.localizedDescription)"
        }
    }
}

/// Settings → Diagnostics. Toggles file-based diagnostic logging (device-local,
/// via `DevicePreferencesStore`) and triggers an export package. The toggle is a
/// write-through `Binding`: `.task` hydrates `enabled` directly (no write), while
/// only a user tap routes through `set` to persist — so hydration never echoes
/// back as a spurious write.
///
/// The include `.sheet` + `.fileExporter` are hosted by `DebugPage` on the
/// `SettingsDetailScreen` container (not here on the `Section`) — see
/// `DiagnosticsExportModel`. This section only renders the rows + drives the model.
struct DiagnosticsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: DiagnosticsExportModel

    var body: some View {
        Section("Diagnostics") {
            Toggle("Diagnostic logging", isOn: loggingBinding)
            Text("Records task changes to on-device log files for troubleshooting. Logs stay on this device and are shared only when you create and send a package.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                model.showInclude = true
            } label: {
                if model.isPreparing {
                    ProgressView()
                } else {
                    Text("Prepare diagnostic package…")
                }
            }
            .disabled(model.isPreparing)
            if let lastError = model.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(RainbowPalette.cautionAmber.ink)
            }
        }
        .task { await model.hydrate(environment) }
    }

    private var loggingBinding: Binding<Bool> {
        Binding(
            get: { model.enabled },
            set: { model.setLogging($0, environment) }
        )
    }
}
