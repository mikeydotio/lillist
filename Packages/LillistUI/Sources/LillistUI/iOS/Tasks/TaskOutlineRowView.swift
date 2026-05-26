#if os(iOS)
import SwiftUI
import LillistCore

/// Single row in the outline list: optional disclosure chevron + the
/// shared `TaskRowView`. Depth is rendered as a leading inset so the
/// outline shape stays visible at a glance.
public struct TaskOutlineRowView: View {
    public let row: FlatTaskRow
    public let isCollapsed: Bool
    public let onToggleDisclosure: () -> Void
    public let onStatusClick: () -> Void
    public let onStatusSet: (Status) -> Void

    private static let indentPerLevel: CGFloat = 22
    private static let chevronWidth: CGFloat = 22

    public init(
        row: FlatTaskRow,
        isCollapsed: Bool,
        onToggleDisclosure: @escaping () -> Void,
        onStatusClick: @escaping () -> Void,
        onStatusSet: @escaping (Status) -> Void
    ) {
        self.row = row
        self.isCollapsed = isCollapsed
        self.onToggleDisclosure = onToggleDisclosure
        self.onStatusClick = onStatusClick
        self.onStatusSet = onStatusSet
    }

    public var body: some View {
        HStack(spacing: 0) {
            if row.depth > 0 {
                Color.clear.frame(width: CGFloat(row.depth) * Self.indentPerLevel)
            }
            chevron
            TaskRowView(
                task: row.node.record,
                tagNames: row.node.tagNames,
                onStatusClick: onStatusClick,
                onStatusSet: onStatusSet
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
#endif
