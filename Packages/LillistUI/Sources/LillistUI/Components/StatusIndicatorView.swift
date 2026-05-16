import SwiftUI
import LillistCore

/// Clickable status indicator per design Section 7.
public struct StatusIndicatorView: View {
    public var status: Status
    public var onClick: () -> Void
    public var onLongPress: () -> Void

    public init(status: Status, onClick: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.status = status
        self.onClick = onClick
        self.onLongPress = onLongPress
    }

    public var body: some View {
        Button(action: onClick) {
            Image(systemName: StatusGlyph.symbol(for: status))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(status == .closed ? .green : .secondary)
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Cycle status")) {
            onLongPress()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onLongPress() }
        )
    }
}
