import SwiftUI
import LillistCore
import LillistUI

/// Settings → Task Defaults. Defaults that govern new tasks and how
/// lists are ordered (split out of the former combined "Defaults"
/// section).
struct TaskDefaultsPage: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        SettingsDetailScreen("Task Defaults") {
            Section {
                Picker("Task list sort", selection: $prefs.defaultTaskListSort) {
                    ForEach(SortField.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Affects all task lists in the app.")
            }
        }
    }
}
