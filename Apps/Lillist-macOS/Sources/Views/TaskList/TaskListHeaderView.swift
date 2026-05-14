import SwiftUI
import LillistCore

struct TaskListHeaderView: View {
    let title: String
    let count: Int
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Text("\(count)")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) tasks")
            Spacer()
            TaskListSortControl(field: $sortField, ascending: $sortAscending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
