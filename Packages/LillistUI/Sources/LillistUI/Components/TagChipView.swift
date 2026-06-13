import SwiftUI

/// A tag chip in one of two Rainbow Logic styles. Pure-text,
/// non-interactive today.
///
/// - `.pill` (default) — white card capsule with a color swatch and
///   the name; for detail surfaces and standalone tag lists.
/// - `.meta` — bare swatch + muted name, no background; for the dense
///   meta line inside task rows where a full capsule per tag is too
///   loud.
///
/// The swatch color comes from the user's `TagTint` (with its dark
/// desaturation and WCAG clamps) in both styles; text never renders
/// in the tint itself.
///
/// # MARK: When tappable
///
/// When `onRemove: (() -> Void)?` becomes a parameter (planned for
/// the tag-editor surface), the contract changes:
///
/// 1. The chip becomes `Button { onRemove?() } label: { … }` (or
///    adds an inline "x" button to the right of the text).
/// 2. Add `.accessibilityAddTraits(.isButton)` so VoiceOver
///    announces "Button: Tag: work".
/// 3. Add `.accessibilityAction(named: "Remove") { onRemove?() }`
///    so Switch Control / Voice Control / VoiceOver users can
///    invoke removal without performing the visual "x" tap.
///
/// Until then, the read-only `Text` + `.accessibilityLabel("Tag: …")`
/// pattern is the correct contract.
public struct TagChipView: View {
    public enum Style {
        /// White card capsule + swatch + name (detail surfaces).
        case pill
        /// Bare swatch + muted name (task-row meta lines).
        case meta
    }

    public var name: String
    public var tint: TagTint?
    public var style: Style

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    public init(name: String, tint: TagTint? = nil, style: Style = .pill) {
        self.name = name
        self.tint = tint
        self.style = style
    }

    public var body: some View {
        let increaseContrast = overrideIncreaseContrast ?? systemIncreaseContrast
        let swatchColor = tint?.resolved(in: scheme).color ?? LillistColor.textFaint

        Group {
            switch style {
            case .meta:
                HStack(spacing: 5) {
                    swatch(swatchColor, size: 8, increaseContrast: increaseContrast)
                    Text(name)
                        .font(LillistTypography.caption)
                        .foregroundStyle(increaseContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(LillistColor.textMuted))
                }

            case .pill:
                HStack(spacing: 6) {
                    swatch(swatchColor, size: 9, increaseContrast: increaseContrast)
                    Text(name)
                        .font(LillistTypography.subheadline)
                        .foregroundStyle(increaseContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(LillistColor.textBody))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(LillistColor.card))
                .overlay(
                    Capsule().strokeBorder(
                        increaseContrast ? swatchColor.opacity(0.85) : LillistColor.borderSoft,
                        lineWidth: 1
                    )
                )
                .rainbowShadow(.xs)
            }
        }
        .accessibilityLabel(String(localized: "Tag: \(name)", bundle: .module))
    }

    private func swatch(_ color: Color, size: CGFloat, increaseContrast: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if increaseContrast {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.primary, lineWidth: 1)
                }
            }
    }
}
