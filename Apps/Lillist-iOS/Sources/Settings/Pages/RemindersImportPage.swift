import SwiftUI
import LillistUI

/// Settings → Tasks from Reminders. Wraps the env-coupled
/// `RemindersImportSection` (enable toggle, list picker, drain control) in the
/// shared sub-page chrome.
struct RemindersImportPage: View {
    var body: some View {
        SettingsDetailScreen("Tasks from Reminders") {
            RemindersImportSection()
        }
    }
}
