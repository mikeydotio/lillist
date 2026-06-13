import SwiftUI

/// The volumetric Rainbow Logic pill button: capsule, inset top
/// highlight, hue glow, lift-on-nothing/squish-on-press. Pick the
/// variant by *function*, never by what looks nice:
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
            .background(fill(pressed: pressed))
            .overlay {
                if variant != .ghost {
                    RainbowTopHighlight(shape: Capsule(), strength: pressed ? 0.3 : 0.55)
                }
            }
            .modifier(GlowModifier(variant: variant, pressed: pressed))
            .opacity(configuration.isPressed && variant == .ghost ? 0.7 : 1)
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

    @ViewBuilder
    private func fill(pressed: Bool) -> some View {
        let shape = Capsule()
        switch variant {
        case .lavender:  shape.fill(pressedAware(LillistColor.lavender, pressed))
        case .orange:    shape.fill(pressedAware(RainbowPalette.actionOrange.base, pressed))
        case .green:     shape.fill(pressedAware(RainbowPalette.growthGreen.base, pressed))
        case .blue:      shape.fill(pressedAware(RainbowPalette.focusBlue.base, pressed))
        case .purple:    shape.fill(pressedAware(RainbowPalette.scriptPurple.base, pressed))
        case .rainbow:   shape.fill(RainbowGradient.horizontal).overlay(shape.fill(.black.opacity(pressed ? 0.08 : 0)))
        case .secondary: shape.fill(pressedAware(LillistColor.card, pressed))
        case .ghost:     shape.fill(pressed ? AnyShapeStyle(LillistColor.sunken) : AnyShapeStyle(.clear))
        }
    }

    /// Pressed fills darken via the inner-shadow well treatment.
    private func pressedAware(_ color: Color, _ pressed: Bool) -> AnyShapeStyle {
        pressed
            ? AnyShapeStyle(color.shadow(.inner(color: .black.opacity(0.18), radius: 2.5, y: 1)))
            : AnyShapeStyle(color)
    }

    /// Glow belongs to the lit object: suppressed while pressed (the
    /// object is "down") and absent on flat variants.
    private struct GlowModifier: ViewModifier {
        let variant: Variant
        let pressed: Bool

        func body(content: Content) -> some View {
            switch variant {
            case .lavender: content.shadow(color: RainbowPalette.scriptPurple.base.opacity(pressed ? 0.08 : 0.20), radius: 8, y: 6)
            case .orange:   content.rainbowGlow(RainbowPalette.actionOrange, radius: pressed ? 3 : 6)
            case .green:    content.rainbowGlow(RainbowPalette.growthGreen, radius: pressed ? 3 : 6)
            case .blue:     content.rainbowGlow(RainbowPalette.focusBlue, radius: pressed ? 3 : 6)
            case .purple:   content.rainbowGlow(RainbowPalette.scriptPurple, radius: pressed ? 3 : 6)
            case .rainbow:  content.shadow(color: RainbowPalette.scriptPurple.base.opacity(pressed ? 0.10 : 0.22), radius: 10, y: 8)
            case .secondary: content.rainbowShadow(.sm)
            case .ghost:    content
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
