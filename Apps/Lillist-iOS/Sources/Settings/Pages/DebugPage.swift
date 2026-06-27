import SwiftUI
import UniformTypeIdentifiers
import LillistCore
import LillistUI

/// Settings → Debug. Developer/diagnostic surface: crash reporting and
/// diagnostic logging, plus the destructive full data-store reset used
/// when the local store is suspected corrupt.
///
/// The diagnostics export modals (`.sheet` + `.fileExporter`) are hosted **here**
/// on the `SettingsDetailScreen` container, not inside `DiagnosticsSection`'s
/// `Section`: a `.sheet` attached to Form-row content inside this pushed
/// nav-destination-in-a-sheet present-then-dismisses and nukes the whole
/// Settings sheet (see `DiagnosticsExportModel`).
struct DebugPage: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var diagnostics = DiagnosticsExportModel()

    var body: some View {
        SettingsDetailScreen("Debug") {
            CrashReportingSection(prefs: $prefs)
            DiagnosticsSection(model: diagnostics)
            ResetDataStoreSection()
        }
        .sheet(isPresented: $diagnostics.showInclude, onDismiss: {
            // Build + present the exporter only AFTER the include sheet has fully
            // dismissed, so the two presentations never conflict.
            diagnostics.includeSheetDismissed(environment)
        }) {
            DiagnosticsIncludeSheet(
                includeLogs: $diagnostics.includeLogs,
                includeStore: $diagnostics.includeStore,
                onCreate: { diagnostics.requestCreate() },
                onCancel: { diagnostics.showInclude = false }
            )
        }
        .fileExporter(
            isPresented: $diagnostics.showExporter,
            document: diagnostics.exportDocument,
            contentType: .zip,
            defaultFilename: "Lillist-Diagnostics"
        ) { result in
            if case .failure(let error) = result {
                diagnostics.lastError = "Export failed: \(error.localizedDescription)"
            }
            diagnostics.exportDocument = nil
        }
    }
}
