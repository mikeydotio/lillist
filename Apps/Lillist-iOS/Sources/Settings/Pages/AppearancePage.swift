import SwiftUI
import LillistCore
import LillistUI

/// Settings → Appearance. The default tint applied to newly-created
/// tags (split out of the former combined "Defaults" section).
struct AppearancePage: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        SettingsDetailScreen("Appearance") {
            Section {
                ColorPicker("Default tag tint", selection: tintBinding)
            } footer: {
                Text("Applied to new tags. Existing tags keep their custom color.")
            }
        }
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: prefs.defaultTagTintHex) ?? .gray },
            set: { prefs.defaultTagTintHex = $0.toHex() ?? LillistTokens.defaultTagTintHex }
        )
    }
}
