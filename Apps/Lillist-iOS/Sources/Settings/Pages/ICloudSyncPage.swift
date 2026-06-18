import SwiftUI
import LillistUI

/// Settings → iCloud Sync. Wraps the env-coupled `ICloudSyncSection`
/// (the sync toggle plus its migration sheets/dialogs) in the shared
/// sub-page chrome.
struct ICloudSyncPage: View {
    var body: some View {
        SettingsDetailScreen("iCloud Sync") {
            ICloudSyncSection()
        }
    }
}
