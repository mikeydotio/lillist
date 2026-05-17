import SwiftUI
import LillistCore

struct TaskListSortControl: View {
    @Binding var field: SortField
    @Binding var ascending: Bool

    var body: some View {
        Menu {
            ForEach(SortField.allCases, id: \.self) { f in
                Button {
                    if field == f { ascending.toggle() } else { field = f }
                } label: {
                    Label(f.displayName, systemImage: field == f ? (ascending ? "arrow.up" : "arrow.down") : "")
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(String(localized: "Sort tasks by \(field.displayName)"))
    }
}

private extension SortField {
    var displayName: String {
        switch self {
        case .manualPosition: return "Manual"
        case .deadline:   return "Deadline"
        case .start:      return "Start"
        case .title:      return "Title"
        case .createdAt:  return "Created"
        case .modifiedAt: return "Modified"
        case .closedAt:   return "Closed"
        case .status:     return "Status"
        }
    }
}
