import SwiftUI
import LillistCore
import LillistUI

struct GeneralSection: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        // Split into two sub-sections so each control gets its own
        // footer. The second section omits a header so the two render
        // visually adjacent under the single "Defaults" heading.
        Section {
            Picker("Task list sort", selection: $prefs.defaultTaskListSort) {
                ForEach(SortField.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Defaults")
        } footer: {
            Text("Affects all task lists in the app.")
        }
        Section {
            ColorPicker("Default tag tint", selection: tintBinding)
        } footer: {
            Text("Applied to new tags. Existing tags keep their custom color.")
        }
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: prefs.defaultTagTintHex) ?? .gray },
            set: { prefs.defaultTagTintHex = $0.toHex() ?? LillistTokens.defaultTagTintHex }
        )
    }
}

