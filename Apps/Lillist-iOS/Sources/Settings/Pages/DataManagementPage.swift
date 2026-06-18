import SwiftUI
import LillistCore
import LillistUI

/// Settings → Data Management. Trash retention/empty plus data
/// export/import, grouped as the data-stewardship surface.
struct DataManagementPage: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        SettingsDetailScreen("Data Management") {
            TrashSection(prefs: $prefs)
            AdvancedSection()
        }
    }
}
