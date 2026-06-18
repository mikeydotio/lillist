import SwiftUI
import LillistCore
import LillistUI

/// Settings → Debug. Developer/diagnostic surface: crash reporting and
/// diagnostic logging, plus the destructive full data-store reset used
/// when the local store is suspected corrupt.
struct DebugPage: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        SettingsDetailScreen("Debug") {
            CrashReportingSection(prefs: $prefs)
            DiagnosticsSection()
            ResetDataStoreSection()
        }
    }
}
