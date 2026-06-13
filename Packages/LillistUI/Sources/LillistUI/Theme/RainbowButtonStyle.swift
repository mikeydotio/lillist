import SwiftUI

/// The Rainbow Glass pill button: a capsule of tinted Liquid Glass
/// (degrading to a solid color below OS 26) with squish-on-press. Pick
/// the variant by *function*, never by what looks nice:
///
/// - `.lavender` — the signature add/capture action
/// - `.orange` — urgent/destructive confirms
/// - `.green` — routine confirms
/// - `.blue` — work/focus actions
/// - `.purple` — system/scripting actions
/// - `.rainbow` — hero/success CTAs only (a sanctioned full-gradient
///   moment; never for everyday buttons)
/// - `.secondary` — neutral raised white
/// - `.ghost` — low-emphasis inline actions
public struct RainbowButtonStyle: ButtonStyle {
    public enum Variant: Sendable {
        case lavender, orange, green, blue, purple, rainbow, secondary, ghost
    }

    public enum Size: Sendable {
        case sm, md

        var height: CGFloat { self == .sm ? 32 : 40 }
        var hPadding: CGFloat { self == .sm ? 14 : 20 }
        var font: Font { self == .sm ? LillistTypography.buttonSm : LillistTypography.buttonMd }
    }

    public var variant: Variant
    public var size: Size

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion

    public init(variant: Variant = .lavender, size: Size = .md) {
        self.variant = variant
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let reduce = overrideReduceMotion ?? systemReduceMotion

        return configuration.label
            .font(size.font)
            .foregroundStyle(textColor)
            .padding(.horizontal, size.hPadding)
            .frame(minHeight: size.height)
            .modifier(ButtonSurface(variant: variant, pressed: pressed))
            .opacity(pressed && variant == .ghost ? 0.7 : 1)
            .scaleEffect(pressed && !reduce ? 0.985 : 1)
            .offset(y: pressed && !reduce ? 1 : 0)
            .animation(reduce ? nil : LillistMotion.squish(LillistMotion.fast), value: pressed)
            .contentShape(Capsule())
    }

    private var textColor: Color {
        switch variant {
        case .lavender:  RainbowPalette.scriptPurple.ink
        case .orange, .green, .blue, .purple, .rainbow: .white
        case .secondary: LillistColor.textBody
        case .ghost:     LillistColor.textMuted
        }
    }

    /// The capsule surface per variant. Functional hues and the
    /// signature lavender become tinted Liquid Glass via `GlassSurface`
    /// (glass on OS 26, solid color below — never frosted, since these
    /// are fills, not chrome). `secondary` is neutral glass; `rainbow`
    /// keeps the sanctioned hero gradient; `ghost` stays flat. Glass
    /// supplies the highlight/contact-shadow the old `RainbowTopHighlight`
    /// + per-hue glow used to fake; press feedback is the squish.
    private struct ButtonSurface: ViewModifier {
        let variant: Variant
        let pressed: Bool

        func body(content: Content) -> some View {
            switch variant {
            case .lavender:
                content.glassSurface(.statusTinted(LillistColor.lavender), in: Capsule())
            case .orange:
                content.glassSurface(.statusTinted(RainbowPalette.actionOrange.base), in: Capsule())
            case .green:
                content.glassSurface(.statusTinted(RainbowPalette.growthGreen.base), in: Capsule())
            case .blue:
                content.glassSurface(.statusTinted(RainbowPalette.focusBlue.base), in: Capsule())
            case .purple:
                content.glassSurface(.statusTinted(RainbowPalette.scriptPurple.base), in: Capsule())
            case .rainbow:
                content.background(RainbowGradient.horizontal, in: Capsule())
            case .secondary:
                content.glassSurface(.control, in: Capsule())
            case .ghost:
                content.background(
                    pressed ? AnyShapeStyle(LillistColor.sunken) : AnyShapeStyle(.clear),
                    in: Capsule()
                )
            }
        }
    }
}

extension ButtonStyle where Self == RainbowButtonStyle {
    /// `.buttonStyle(.rainbow(.lavender))` — see `RainbowButtonStyle`.
    public static func rainbow(
        _ variant: RainbowButtonStyle.Variant = .lavender,
        size: RainbowButtonStyle.Size = .md
    ) -> RainbowButtonStyle {
        RainbowButtonStyle(variant: variant, size: size)
    }
}
