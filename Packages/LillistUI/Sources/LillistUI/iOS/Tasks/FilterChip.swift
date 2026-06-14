#if os(iOS)
import SwiftUI

/// Pill-shaped toggle button used in the Tasks screen's expanding filter
/// header. Unselected is a raised white card chip; selected fills with
/// the signature lavender + purple ink (mirrors the lavender hero
/// button — selection is a "kept" state, not an alert).
public struct FilterChip: View {
    public let title: String
    public let isSelected: Bool
    public let action: () -> Void

    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let increaseContrast = overrideIncreaseContrast ?? systemIncreaseContrast
        Button(action: action) {
            Text(title)
                .font(LillistTypography.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? LillistColor.lavender : LillistColor.card)
                }
                .foregroundStyle(isSelected ? RainbowPalette.scriptPurple.ink : LillistColor.textBody)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? RainbowPalette.scriptPurple.base.opacity(increaseContrast ? 0.9 : 0.35)
                                : (increaseContrast ? LillistColor.borderStrong : LillistColor.borderHair),
                            lineWidth: 1
                        )
                }
                .rainbowShadow(.xs)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
