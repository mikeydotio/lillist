import SwiftUI
import UniformTypeIdentifiers
import LillistCore
import LillistUI

/// Settings → Diagnostics. Toggles file-based diagnostic logging (device-local,
/// via `DevicePreferencesStore`) and prepares an export package. The toggle is a
/// write-through `Binding`: `.task` hydrates `enabled` directly (no write), while
/// only a user tap routes through `set` to persist — so hydration never echoes
/// back as a spurious write.
struct DiagnosticsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var enabled = false
    @State private var didHydrate = false
    @State private var showInclude = false
    @State private var wantsExport = false
    @State private var includeLogs = true
    @State private var includeStore = true
    @State private var isPreparing = false
    @State private var exportDocument: DiagnosticZipDocument?
    @State private var showExporter = false
    @State private var lastError: String?

    var body: some View {
        Section("Diagnostics") {
            Toggle("Diagnostic logging", isOn: loggingBinding)
            Text("Records task changes to on-device log files for troubleshooting. Logs stay on this device and are shared only when you create and send a package.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showInclude = true
            } label: {
                if isPreparing {
                    ProgressView()
                } else {
                    Text("Prepare diagnostic package…")
                }
            }
            .disabled(isPreparing)
            if let lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(RainbowPalette.cautionAmber.ink)
            }
        }
        .task {
            // One-shot hydration: if the user already toggled while this read was
            // in flight, `didHydrate` is already true and the stale read is dropped.
            let initial = await environment.devicePreferences.diagnosticLoggingEnabled()
            if !didHydrate { enabled = initial; didHydrate = true }
        }
        .sheet(isPresented: $showInclude, onDismiss: {
            // Build + present the exporter only AFTER the include sheet has fully
            // dismissed, so the two presentations never conflict.
            if wantsExport { wantsExport = false; Task { await prepare() } }
        }) {
            DiagnosticsIncludeSheet(
                includeLogs: $includeLogs,
                includeStore: $includeStore,
                onCreate: { wantsExport = true; showInclude = false },
                onCancel: { showInclude = false }
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: "Lillist-Diagnostics"
        ) { result in
            if case .failure(let error) = result {
                lastError = "Export failed: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
    }

    private var loggingBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                didHydrate = true   // user is authoritative now — .task must not overwrite
                enabled = newValue
                Task {
                    await environment.devicePreferences.setDiagnosticLoggingEnabled(newValue)
                    await environment.diagnosticLog.setEnabled(newValue)
                }
            }
        )
    }

    private func prepare() async {
        isPreparing = true
        lastError = nil
        defer { isPreparing = false }
        let metadata = DiagnosticPackageBuilder.Metadata(
            buildVersion: environment.buildVersion,
            osVersion: environment.osVersion,
            deviceModel: environment.deviceModel,
            exportedAt: Date(),
            diagnosticLoggingEnabled: enabled
        )
        let builder = DiagnosticPackageBuilder(
            diagnosticsDir: await environment.diagnosticLog.diagnosticsDirectory(),
            storeURL: environment.storeURL,
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
