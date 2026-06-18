import SwiftUI
import LillistCore
import LillistUI

/// Settings → Quick Capture. Wraps the env-coupled `QuickCaptureSection`
/// (floating + button toggle, Shortcuts link) in the shared sub-page
/// chrome.
struct QuickCapturePage: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        SettingsDetailScreen("Quick Capture") {
            QuickCaptureSection(prefs: $prefs)
        }
    }
}
