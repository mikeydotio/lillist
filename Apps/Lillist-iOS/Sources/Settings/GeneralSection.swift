import SwiftUI
import LillistCore
import LillistUI

struct GeneralSection: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        Section("Defaults") {
            Picker("Task list sort", selection: $prefs.defaultTaskListSort) {
                ForEach(SortField.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            ColorPicker("Default tag tint", selection: tintBinding)
        }
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: prefs.defaultTagTintHex) ?? .gray },
            set: { prefs.defaultTagTintHex = $0.toHex() ?? LillistTokens.defaultTagTintHex }
        )
    }
}

