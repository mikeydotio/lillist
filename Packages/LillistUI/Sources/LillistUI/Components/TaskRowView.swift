import SwiftUI
import LillistCore

public struct TaskRowView: View {
    public var task: TaskStore.TaskRecord
    public var tagNames: [String]
    public var onStatusClick: () -> Void
    public var onStatusLongPress: () -> Void

    public init(
        task: TaskStore.TaskRecord,
        tagNames: [String],
        onStatusClick: @escaping () -> Void,
        onStatusLongPress: @escaping () -> Void
    ) {
        self.task = task
        self.tagNames = tagNames
        self.onStatusClick = onStatusClick
        self.onStatusLongPress = onStatusLongPress
    }

    public var body: some View {
        HStack(spacing: 8) {
            StatusIndicatorView(
                status: task.status,
                onClick: onStatusClick,
                onLongPress: onStatusLongPress
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.status == .closed)
                    .foregroundStyle(task.status == .closed ? .secondary : .primary)
                    .lineLimit(1)

                if !tagNames.isEmpty || task.deadline != nil {
                    HStack(spacing: 4) {
                        ForEach(tagNames, id: \.self) { TagChipView(name: $0) }
                        if let deadline = task.deadline {
                            Label(deadline.formatted(date: .abbreviated, time: task.deadlineHasTime ? .shortened : .omitted),
                                  systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Drag handle")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(StatusGlyph.accessibilityLabel(for: task.status))")
    }
}
