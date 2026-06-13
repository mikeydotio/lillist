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

            TaskRowLabel(task: task, tagNames: tagNames)
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

/// The textual portion of a task row: title plus the tag/deadline
/// caption line. Extracted from `TaskRowView` so the iOS outline row
/// can wrap *only this region* in its `NavigationLink` + drag-reorder
/// gesture while the status control stays outside both — a row-level
/// long-press drag gesture laid over the status control eats its tap
/// (see engineering-notes 2026-06-12). `TaskRowView` (macOS, detail
/// surfaces) composes it back inline, unchanged visually.
public struct TaskRowLabel: View {
    public var task: TaskStore.TaskRecord
    public var tagNames: [String]

    public init(task: TaskStore.TaskRecord, tagNames: [String]) {
        self.task = task
        self.tagNames = tagNames
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .font(LillistTypography.headline)
                .strikethrough(task.status == .closed)
                .foregroundStyle(task.status == .closed ? LillistColor.textFaint : LillistColor.textStrong)

            if !tagNames.isEmpty || task.deadline != nil {
                HStack(spacing: LillistSpacing.s) {
                    if let deadline = task.deadline {
                        let overdue = Self.isOverdue(
                            deadline: deadline,
                            hasTime: task.deadlineHasTime,
                            status: task.status
                        )
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11, weight: .semibold))
                            Text(deadline.formatted(date: .abbreviated, time: task.deadlineHasTime ? .shortened : .omitted))
                                .font(LillistTypography.caption)
                        }
                        .foregroundStyle(overdue ? RainbowPalette.actionOrange.ink : LillistColor.textMuted)
                    }
                    ForEach(tagNames, id: \.self) { TagChipView(name: $0, style: .meta) }
                }
            }
        }
    }

    /// Whether a deadline reads as overdue: past `now` for timed
    /// deadlines, before today for date-only ones. Closed tasks are
    /// never overdue — done is done. `nonisolated` static value math
    /// so tests and background callers don't cross the View's
    /// MainActor boundary.
    public nonisolated static func isOverdue(
        deadline: Date?,
        hasTime: Bool,
        status: Status,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let deadline, status != .closed else { return false }
        if hasTime { return deadline < now }
        return calendar.startOfDay(for: deadline) < calendar.startOfDay(for: now)
    }
}

/// Adds a VoiceOver reorder action for each *wired* closure. An action is
/// attached only when its closure is non-nil, so surfaces that don't
/// support a given operation (e.g. iOS lists without indent/outdent
/// plumbing) advertise no phantom no-op action.
private struct ReorderActionsModifier: ViewModifier {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?

    func body(content: Content) -> some View {
        let dispatch = ReorderActionDispatch(
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onIndent: onIndent,
            onOutdent: onOutdent
        )
        return dispatch.availableActions.reduce(AnyView(content)) { view, action in
            AnyView(
                view.accessibilityAction(named: Self.label(for: action)) {
                    dispatch.invoke(action)
                }
            )
        }
    }

    /// `.module`-localized VoiceOver name for each reorder action, built from
    /// a compile-time literal so the strings are extractable into the catalog
    /// (a runtime `String(localized: .init(action.accessibilityKey))` is NOT
    /// extractable, which previously left these four English-only and
    /// invisible to the localization-drift lint). The literals must match
    /// `ReorderAction.accessibilityKey` — pinned by `ReorderActionDispatchTests`.
    private static func label(for action: ReorderAction) -> Text {
        switch action {
        case .moveUp:   return Text(String(localized: "Move up", bundle: .module))
        case .moveDown: return Text(String(localized: "Move down", bundle: .module))
        case .indent:   return Text(String(localized: "Indent", bundle: .module))
        case .outdent:  return Text(String(localized: "Outdent", bundle: .module))
        }
    }
}
