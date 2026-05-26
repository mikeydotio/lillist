#if os(iOS)
import SwiftUI

/// Pill-shaped toggle button used in the Tasks screen's expanding filter
/// header. Selected state is filled with the accent tint; unselected is
/// outlined.
public struct FilterChip: View {
    public let title: String
    public let isSelected: Bool
    public let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(LillistTypography.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                }
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : Color(.separator),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
