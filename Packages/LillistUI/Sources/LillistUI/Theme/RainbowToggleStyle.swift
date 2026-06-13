import SwiftUI

/// The tactile Rainbow Logic switch: an inset sunken track with a
/// raised, top-lit thumb that squishes across. On-state fills with a
/// functional hue (`focusBlue` by default — settings are "work
/// configuration" in the functional-color language).
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
                            .overlay(RainbowTopHighlight(shape: Circle()))
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

    private func trackFill(isOn: Bool) -> AnyShapeStyle {
        isOn
            ? AnyShapeStyle(onColor.shadow(.inner(color: .black.opacity(0.12), radius: 1.5, y: 1)))
            : AnyShapeStyle(
                LillistColor.sunken
                    .shadow(.inner(color: .black.opacity(0.09), radius: 2, y: 1))
                    .shadow(.inner(color: .black.opacity(0.05), radius: 0.5, y: 0.5))
            )
    }
}

extension ToggleStyle where Self == RainbowToggleStyle {
    /// `.toggleStyle(.rainbow)` — see `RainbowToggleStyle`.
    public static var rainbow: RainbowToggleStyle { RainbowToggleStyle() }
}
