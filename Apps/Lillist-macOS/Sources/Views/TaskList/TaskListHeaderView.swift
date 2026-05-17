import SwiftUI
import LillistCore

struct TaskListHeaderView: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Text("\(count)")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) tasks")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
