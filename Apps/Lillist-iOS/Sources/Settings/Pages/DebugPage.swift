import SwiftUI
import LillistCore
import LillistUI

/// Settings → Debug. Developer/diagnostic surface: crash reporting and
/// diagnostic logging, plus the destructive full data-store reset used
/// when the local store is suspected corrupt.
///
/// The diagnostics modals are hosted **here** on the `SettingsDetailScreen`
/// container through one `.sheet(item:)`, not inside `DiagnosticsSection`'s
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
        .sheet(item: $diagnostics.sheet, onDismiss: {
            // After the include sheet dismisses, build + present the share sheet;
            // after the share sheet dismisses, clean up the temp package.
            diagnostics.sheetDismissed(environment)
        }) { sheet in
            switch sheet {
            case .include:
                DiagnosticsIncludeSheet(
                    includeLogs: $diagnostics.includeLogs,
                    includeStore: $diagnostics.includeStore,
                    onCreate: { diagnostics.requestExport() },
                    onCancel: { diagnostics.sheet = nil }
                )
            case .share(let url):
                ShareSheet(activityItems: [url])
            }
        }
    }
}
