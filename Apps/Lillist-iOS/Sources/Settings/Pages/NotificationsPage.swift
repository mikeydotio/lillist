import SwiftUI
import LillistCore
import LillistUI

/// Settings → Notifications. Wraps the env-coupled `NotificationsSection`
/// (all-day reminder time, morning summary, permission status) in the
/// shared sub-page chrome.
struct NotificationsPage: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        SettingsDetailScreen("Notifications") {
            NotificationsSection(prefs: $prefs)
        }
    }
}
