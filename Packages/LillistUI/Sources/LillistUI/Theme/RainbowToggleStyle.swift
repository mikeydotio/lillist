import SwiftUI

/// The Rainbow Glass switch: a clean flat track with a solid white
/// thumb that squishes across — the iOS-26-native shape (a 20pt thumb is
/// too small for literal glass to read, and the system toggle keeps a
/// solid knob). On-state fills with a functional hue (`focusBlue` by
/// default — settings are "work configuration" in the functional-color
/// language). The faux-depth of the old design (inset-well track,
/// top-lit thumb) is retired; the thumb keeps only a light contact
/// shadow for separation.
///
/// Used on settings surfaces of *both* platforms (the full-whimsy
/// decision); honors Reduce Motion and Increase Contrast.
public struct RainbowToggleStyle: ToggleStyle {
    public var onColor: Color

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion
    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    public init(onColor: Color = RainbowPalette.focusBlue.base) {
        self.onColor = onColor
    }

    private static let trackSize = CGSize(width: 44, height: 26)
    private static let thumbSize: CGFloat = 20

    public func makeBody(configuration: Configuration) -> some View {
        let reduce = overrideReduceMotion ?? systemReduceMotion
        let increaseContrast = overrideIncreaseContrast ?? systemIncreaseContrast

        HStack {
            configuration.label
            Spacer(minLength: LillistSpacing.s)
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(trackFill(isOn: configuration.isOn))
                    .overlay {
                        if increaseContrast {
                            Capsule().strokeBorder(
                                configuration.isOn ? onColor : LillistColor.borderStrong,
                                lineWidth: 1
                            )
                        }
                    }
                    .frame(width: Self.trackSize.width, height: Self.trackSize.height)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: Self.thumbSize, height: Self.thumbSize)
                            .rainbowShadow(.xs)
                            .padding(.horizontal, 3)
                    }
                    .animation(reduce ? nil : LillistMotion.squish(LillistMotion.base), value: configuration.isOn)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)  // the Toggle's own element carries the a11y contract
        }
        .contentShape(Rectangle())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    /// Flat track: the functional hue when on, the neutral sunken color
    /// when off. The old inset-well inner shadows are retired.
    private func trackFill(isOn: Bool) -> AnyShapeStyle {
        isOn ? AnyShapeStyle(onColor) : AnyShapeStyle(LillistColor.sunken)
    }
}

extension ToggleStyle where Self == RainbowToggleStyle {
    /// `.toggleStyle(.rainbow)` — see `RainbowToggleStyle`.
    public static var rainbow: RainbowToggleStyle { RainbowToggleStyle() }
}
