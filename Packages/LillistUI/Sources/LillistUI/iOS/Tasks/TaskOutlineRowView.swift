// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI
import LillistCore

/// Single row in the outline list: optional disclosure chevron, the
/// status indicator, and the textual label. Depth is rendered as a
/// leading inset so the outline shape stays visible at a glance.
///
/// The label region is handed to the caller through `linkContent` so
/// the screen can wrap *only the text* in a tap gesture (`.onTapGesture`
/// to open the editor) and the drag-reorder gesture. The chevron and
/// status indicator are constructed outside that closure by design — a
/// row-level long-press drag gesture laid over interactive controls
/// eats their taps, which shipped as the "tapping the status circle
/// does nothing" regression (engineering-notes 2026-06-12); a `Button`
/// in the closure inverts it and starves the long-press (2026-06-17).
/// This API shape makes both unrepresentable: the closure only ever
/// receives the inert text label.
/// The tappable text region `TaskOutlineRowView` hands to its
/// `linkContent` closure — title, tag chips, deadline caption, and the
/// trailing flexible space. The only part of the row a tap or drag
/// gesture may cover. Standalone (not nested) so the closure's parameter
/// type doesn't depend on the row's generic parameter — nesting it would
/// make `LinkContent` inference circular.
public struct TaskOutlineRowLabel: View {
    let task: TaskStore.TaskRecord
    let tagNames: [String]

    public var body: some View {
        HStack(spacing: 0) {
            TaskRowLabel(task: task, tagNames: tagNames)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

public struct TaskOutlineRowView<LinkContent: View>: View {
    public let row: FlatTaskRow
    public let isCollapsed: Bool
    /// When `true`, this row is the cell the in-flight dragged row will nest
    /// under, so its card shows the gentle drop-target-parent border.
    public let isDropTargetParent: Bool
    public let onToggleDisclosure: () -> Void
    public let onStatusClick: () -> Void
    public let onStatusSet: (Status) -> Void
    private let linkContent: (TaskOutlineRowLabel) -> LinkContent

    private static var indentPerLevel: CGFloat { LillistDragTokens.indentPerLevel }
    private static var chevronWidth: CGFloat { 22 }

    public init(
        row: FlatTaskRow,
        isCollapsed: Bool,
        isDropTargetParent: Bool = false,
        onToggleDisclosure: @escaping () -> Void,
        onStatusClick: @escaping () -> Void,
        onStatusSet: @escaping (Status) -> Void,
        @ViewBuilder linkContent: @escaping (TaskOutlineRowLabel) -> LinkContent
    ) {
        self.row = row
        self.isCollapsed = isCollapsed
        self.isDropTargetParent = isDropTargetParent
        self.onToggleDisclosure = onToggleDisclosure
        self.onStatusClick = onStatusClick
        self.onStatusSet = onStatusSet
        self.linkContent = linkContent
    }

    public var body: some View {
        HStack(spacing: 0) {
            if row.depth > 0 {
                Color.clear.frame(width: CGFloat(row.depth) * Self.indentPerLevel)
            }
            chevron
            // Mirrors the layout `TaskRowView` produces (it is no longer
            // used here so the status control can sit outside the link):
            // the Rainbow card wraps [status — s — label]; the depth
            // indent and chevron stay outside it so the outline shape
            // reads against the workspace.
            HStack(spacing: LillistSpacing.s) {
                StatusIndicatorView(
                    status: row.node.record.status,
                    onClick: onStatusClick,
                    onSetStatus: onStatusSet
                )
                linkContent(TaskOutlineRowLabel(
                    task: row.node.record,
                    tagNames: row.node.tagNames
                ))
            }
            .padding(.vertical, 1)
            .padding(.leading, LillistSpacing.xs)
            .padding(.trailing, LillistSpacing.m)
            .rainbowCard(
                accent: StatusPalette.color(for: row.node.record.status),
                isDone: row.node.record.status == .closed,
                border: isDropTargetParent ? .dropTargetParent : .hairline
            )
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if row.hasChildren {
            Button(action: onToggleDisclosure) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: Self.chevronWidth, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed
                ? String(localized: "Expand subtasks", bundle: .module)
                : String(localized: "Collapse subtasks", bundle: .module)
            )
        } else {
            Color.clear.frame(width: Self.chevronWidth, height: 22)
        }
    }
}
