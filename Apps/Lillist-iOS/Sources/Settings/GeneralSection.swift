import SwiftUI
import LillistCore

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
            set: { prefs.defaultTagTintHex = $0.toHex() ?? "#7F8FA6" }
        )
    }
}

private extension SortField {
    var displayName: String {
        switch self {
        case .manualPosition: return "Manual"
        case .start: return "Start date"
        case .deadline: return "Deadline"
        case .title: return "Title"
        case .createdAt: return "Created"
        case .modifiedAt: return "Modified"
        case .closedAt: return "Closed"
        case .status: return "Status"
        }
    }
}
