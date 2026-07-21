import SwiftUI
import UIKit
import LillistCore
import LillistUI

/// Which diagnostics modal is showing. Both are hosted by the **page**
/// (`DebugPage`) on the `SettingsDetailScreen` container via one `.sheet(item:)`
/// — never on a `Section` (a sheet on Form-row content inside this pushed
/// nav-destination-in-a-sheet tears the whole Settings sheet down; see
/// `docs/engineering-notes.md`).
enum DiagnosticsSheet: Identifiable {
    /// Pick what to include in the package.
    case include
    /// The built package — presented as the system share sheet so the user
    /// decides what to do with it (AirDrop, Mail, Save to Files, …).
    case share(URL)

    var id: String {
        switch self {
        case .include: return "include"
        case .share: return "share"
        }
    }
}

/// Owns the Diagnostics export state + pipeline. Lifted out of
/// `DiagnosticsSection` so the modals can be hosted by the page on the
/// `SettingsDetailScreen` container rather than on a `Section`.
@MainActor
@Observable
final class DiagnosticsExportModel {
    var enabled = false
    var includeLogs = true
    var includeStore = true
    var isPreparing = false
    var sheet: DiagnosticsSheet?
    var lastError: String?

    private var didHydrate = false
    private var wantsExport = false
    /// The on-disk package currently being shared; deleted when the share sheet
    /// closes so temp packages don't accumulate.
    private var sharedURL: URL?

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

    /// Tapped "Create" in the include sheet: remember the intent and dismiss it;
    /// the package is built in `sheetDismissed` so the share sheet only presents
    /// after the include sheet has fully gone (one `.sheet` slot, no conflict).
    func requestExport() { wantsExport = true; sheet = nil }

    func sheetDismissed(_ env: AppEnvironment) {
        if wantsExport {
            wantsExport = false
            Task { await buildAndShare(env) }
        } else if let url = sharedURL {
            // The share sheet was dismissed — clean up the temp package.
            try? FileManager.default.removeItem(at: url)
            sharedURL = nil
        }
    }

    private func buildAndShare(_ env: AppEnvironment) async {
        isPreparing = true
        lastError = nil
        defer { isPreparing = false }
        // Issue #54: fold this device's CloudKit provenance into the export so
        // a Dev/Prod split (or an account fault) is visible without a Mac.
        // Issue #66: also fold in export-stall signals (consecutive failure
        // streak + last raw CKError) so a wedged export is self-explaining
        // without SQLite forensics.
        let counts = (try? await env.taskStore.syncCounts()) ?? .init(local: 0, mirrored: 0)
        let sync = SyncDiagnosticsSnapshot.make(
            containerIdentifier: StoreConfiguration.defaultCloudKitContainerIdentifier,
            accountState: env.accountState,
            syncMode: env.currentSyncMode,
            counts: counts,
            exportHealth: await env.syncMonitor.exportHealth
        )
        let metadata = DiagnosticPackageBuilder.Metadata(
            buildVersion: env.buildVersion,
            osVersion: env.osVersion,
            deviceModel: env.deviceModel,
            exportedAt: Date(),
            diagnosticLoggingEnabled: enabled,
            sync: sync
        )
        let builder = DiagnosticPackageBuilder(
            diagnosticsDir: await env.diagnosticLog.diagnosticsDirectory(),
            storeURL: env.storeURL,
            metadata: metadata
        )
        do {
            // Keep the zip on disk and hand its URL to the share sheet; cleaned
            // up in `sheetDismissed` once the user is done with it.
            let zipURL = try await builder.build(options: .init(includeLogs: includeLogs, includeStore: includeStore))
            sharedURL = zipURL
            sheet = .share(zipURL)
        } catch {
            lastError = "Couldn't build diagnostic package: \(error.localizedDescription)"
        }
    }
}

/// Presents the system share sheet for the built diagnostic package. Mirrors the
/// `MailComposerView` representable pattern; hosting `UIActivityViewController` as
/// `.sheet` content (rather than presenting it ourselves) keeps it inside the one
/// container-hosted presentation slot.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Settings → Diagnostics. Toggles file-based diagnostic logging (device-local,
/// via `DevicePreferencesStore`) and exports a package. The toggle is a
/// write-through `Binding`: `.task` hydrates `enabled` directly (no write), while
/// only a user tap routes through `set` to persist — so hydration never echoes
/// back as a spurious write.
///
/// The modals are hosted by `DebugPage` on the `SettingsDetailScreen` container
/// (see `DiagnosticsExportModel`); this section only renders the rows.
struct DiagnosticsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: DiagnosticsExportModel

    var body: some View {
        Section("Diagnostics") {
            Toggle("Diagnostic logging", isOn: loggingBinding)
            Text("Records task changes to on-device log files for troubleshooting. Logs stay on this device and are shared only when you create and send a package.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // Issue #54: the app never surfaced its own CloudKit environment,
            // so a Development/Production split across a device fleet was
            // invisible. A pure, synchronous read of this build's own
            // entitlements — no live container needed.
            LabeledContent("CloudKit Environment") {
                Text(SyncDiagnosticsSnapshot.resolveEnvironment(using: SelfEntitlementReader()).rawValue)
                    .foregroundStyle(.secondary)
            }
            Button {
                model.sheet = .include
            } label: {
                if model.isPreparing {
                    ProgressView()
                } else {
                    Text("Export Diagnostic Package")
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
