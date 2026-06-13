#if os(iOS)
import SwiftUI

/// Persistent floating "+" used across primary iOS surfaces.
///
/// Tap fires `onTap`. Long-press fires `onLongPress` (optional) — surfaces
/// "Quick Capture from clipboard" affordance in callers that want it.
public struct FloatingAddButton: View {
    public var onTap: () -> Void
    public var onLongPress: (() -> Void)?

    public init(onTap: @escaping () -> Void, onLongPress: (() -> Void)? = nil) {
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    /// Compact Rainbow size — 52pt circle (still comfortably above the
    /// 44pt accessibility floor).
    private static let diameter: CGFloat = 52

    public var body: some View {
        Button(action: onTap) {
            Image(systemName: "plus")
                .font(LillistTypography.floatingAddGlyph)
                .foregroundStyle(RainbowPalette.scriptPurple.ink)
                .frame(width: Self.diameter, height: Self.diameter)
                // Rainbow Glass: prominent tinted glass. The brand purple
                // *is* the primary-create signal (functional color), and
                // the interactive glass supplies the fill, specular
                // highlight, and contact shadow the hand-rolled
                // `RainbowTopHighlight` + drop shadow used to fake. The
                // iOS app floors at 26, so this always renders as glass.
                .glassSurface(.primaryAction, in: Circle())
        }
        .buttonStyle(SquishPressStyle())
        .accessibilityLabel(String(localized: "New task", bundle: .module))
        .accessibilityHint(String(localized: "Opens quick capture", bundle: .module))
        .accessibilityAction(named: Text(String(localized: "Capture from clipboard", bundle: .module))) {
            onLongPress?()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: LillistTiming.longPress).onEnded { _ in
                onLongPress?()
            }
        )
    }
}

/// Press feedback for the FAB: the Rainbow squish, gated on Reduce
/// Motion. Local to this file — buttons elsewhere use
/// `RainbowButtonStyle`, which has its own press treatment.
private struct SquishPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let reduce = overrideReduceMotion ?? systemReduceMotion
        return configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? 0.94 : 1)
            .animation(reduce ? nil : LillistMotion.squish(LillistMotion.fast), value: configuration.isPressed)
    }
}
#endif
