import SwiftUI
import UniformTypeIdentifiers
import LillistCore
import LillistUI

/// macOS Preferences → Diagnostics pane (design 2026-06-06). Mirrors the iOS
/// `DiagnosticsSection`: a device-local logging toggle (write-through `Binding`
/// so `.task` hydration never echoes back as a write) plus a package export via
/// `.fileExporter`. The toggle lives in `DevicePreferencesStore`, not `Prefs`,
/// so this pane manages its own `@State` rather than the prefs-stream pattern.
struct DiagnosticsPane: View {
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
        Form {
            Section("Diagnostics") {
                Toggle("Diagnostic logging", isOn: loggingBinding)
                Text("Records task changes to on-device log files for troubleshooting. Logs stay on this Mac and are shared only when you create and save a package.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
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
                        .font(.callout)
                        .foregroundStyle(RainbowPalette.cautionAmber.ink)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: PreferencesMetrics.contentWidth)
        .fixedSize() // pane self-sizes (height); window animates
        .task {
            let initial = await environment.devicePreferences.diagnosticLoggingEnabled()
            if !didHydrate { enabled = initial; didHydrate = true }
        }
        .sheet(isPresented: $showInclude, onDismiss: {
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
            try? FileManager.default.removeItem(at: zipURL)
            showExporter = true
        } catch {
            lastError = "Couldn't build diagnostic package: \(error.localizedDescription)"
        }
    }
}
