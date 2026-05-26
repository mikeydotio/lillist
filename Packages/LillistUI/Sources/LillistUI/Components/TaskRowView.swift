import SwiftUI
import LillistCore

public struct TaskRowView: View {
    public var task: TaskStore.TaskRecord
    public var tagNames: [String]
    public var onStatusClick: () -> Void
    public var onStatusSet: (Status) -> Void
    public var onMoveUp: (() -> Void)?
    public var onMoveDown: (() -> Void)?
    public var onIndent: (() -> Void)?
    public var onOutdent: (() -> Void)?

    public init(
        task: TaskStore.TaskRecord,
        tagNames: [String],
        onStatusClick: @escaping () -> Void,
        onStatusSet: @escaping (Status) -> Void,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onIndent: (() -> Void)? = nil,
        onOutdent: (() -> Void)? = nil
    ) {
        self.task = task
        self.tagNames = tagNames
        self.onStatusClick = onStatusClick
        self.onStatusSet = onStatusSet
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onIndent = onIndent
        self.onOutdent = onOutdent
    }

    public var body: some View {
        HStack(spacing: LillistSpacing.s) {
            StatusIndicatorView(
                status: task.status,
                onClick: onStatusClick,
                onSetStatus: onStatusSet
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .strikethrough(task.status == .closed)
                    .foregroundStyle(task.status == .closed ? .secondary : .primary)

                if !tagNames.isEmpty || task.deadline != nil {
                    HStack(spacing: LillistSpacing.xs) {
                        ForEach(tagNames, id: \.self) { TagChipView(name: $0) }
                        if let deadline = task.deadline {
                            Label(deadline.formatted(date: .abbreviated, time: task.deadlineHasTime ? .shortened : .omitted),
                                  systemImage: "calendar")
                                .font(LillistTypography.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, LillistSpacing.xs + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.composedAccessibilityLabel(task: task, tagNames: tagNames))
        .modifier(ReorderActionsModifier(
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onIndent: onIndent,
            onOutdent: onOutdent
        ))
    }

    /// Composes the row's combined accessibility label. Exposed for unit testing.
    /// Format: "<title>, <status>[, tagged <tags>][, due <date>]"
    public static func composedAccessibilityLabel(
        task: TaskStore.TaskRecord,
        tagNames: [String]
    ) -> String {
        var parts: [String] = [task.title, StatusGlyph.accessibilityLabel(for: task.status)]
        if !tagNames.isEmpty {
            let joined = tagNames.joined(separator: ", ")
            parts.append(String(localized: "tagged \(joined)", bundle: .module))
        }
        if let deadline = task.deadline {
            let formatted = deadline.formatted(
                date: .abbreviated,
                time: task.deadlineHasTime ? .shortened : .omitted
            )
            parts.append(String(localized: "due \(formatted)", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }
}

/// Conditionally adds reorder accessibility actions. Each action is
/// only attached when its closure is non-nil, so callers that don't
/// want a particular action (e.g. iOS surfaces that lack the
/// notification plumbing) get no extraneous announcements.
private struct ReorderActionsModifier: ViewModifier {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: Text("Move up")) { onMoveUp?() }
            .accessibilityAction(named: Text("Move down")) { onMoveDown?() }
            .accessibilityAction(named: Text("Indent")) { onIndent?() }
            .accessibilityAction(named: Text("Outdent")) { onOutdent?() }
    }
}
