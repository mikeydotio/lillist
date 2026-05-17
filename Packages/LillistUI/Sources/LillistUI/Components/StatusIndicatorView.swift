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
                .font(LillistTypography.statusGlyph)
                .foregroundStyle(StatusPalette.color(for: status))   // Plan 17 / Plan 15
                .frame(width: LillistSpacing.xl - 2, height: LillistSpacing.xl - 2)
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
            LongPressGesture(minimumDuration: LillistTiming.longPress).onEnded { _ in onLongPress() }
        )
    }
}
