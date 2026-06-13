import SwiftUI
import LillistCore

/// The Rainbow Logic 3D status cube — the visual heart of a task row.
///
/// Four states, each with a **shape axis** independent of hue so
/// status stays legible for colorblind users and under
/// differentiate-without-color:
///
/// | status  | fill                       | shape                     |
/// |---------|----------------------------|---------------------------|
/// | todo    | raised empty (top-lit)     | empty cube                |
/// | started | focus-blue                 | white left-half fill      |
/// | blocked | action-orange soft         | dashed ink border + bars  |
/// | closed  | growth-green               | white check (squish snap) |
///
/// Purely visual: tap-to-cycle, the explicit-setter menu, hit targets,
/// and every accessibility attribute live in `StatusIndicatorView`,
/// which renders this view as its `Menu` label. The cube also hosts
/// the one-shot confetti burst on a transition into `.closed`
/// (`ConfettiPolicy` decides; Reduce Motion suppresses it).
public struct StatusCubeView: View {
    public var status: Status

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 24
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion

    /// Non-nil while a confetti burst is in flight; the value keys the
    /// burst view's identity so re-closing later restarts cleanly.
    @State private var burstID: UInt64?

    public init(status: Status) {
        self.status = status
    }

    private var cubeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LillistRadius.cube, style: .continuous)
    }

    private var increaseContrast: Bool {
        overrideIncreaseContrast ?? systemIncreaseContrast
    }

    private var reduceMotion: Bool {
        overrideReduceMotion ?? systemReduceMotion
    }

    public var body: some View {
        cube
            .frame(width: size, height: size)
            .overlay {
                if burstID != nil {
                    ConfettiBurstView()
                        // Particles fly past the cube's bounds.
                        .frame(width: size * 3, height: size * 3)
                }
            }
            .onChange(of: status) { old, new in
                guard ConfettiPolicy.shouldBurst(from: old, to: new, reduceMotion: reduceMotion) else { return }
                burstID = (burstID ?? 0) &+ 1
            }
            .task(id: burstID) {
                guard burstID != nil else { return }
                try? await Task.sleep(for: .milliseconds(650))
                burstID = nil
            }
    }

    @ViewBuilder
    private var cube: some View {
        switch status {
        case .todo:
            cubeShape
                .fill(emptyGradient)
                .overlay(cubeShape.strokeBorder(
                    increaseContrast ? LillistColor.borderStrong : LillistColor.borderSoft,
                    lineWidth: 1
                ))
                .overlay(RainbowTopHighlight(shape: cubeShape))

        case .started:
            cubeShape
                .fill(RainbowPalette.focusBlue.base)
                .overlay(litFromAbove)
                .overlay(alignment: .leading) {
                    // Shape axis: leading half filled white.
                    Rectangle()
                        .fill(.white)
                        .frame(width: size / 2)
                        .clipShape(cubeShape)
                        .opacity(0.9)
                }
                .overlay(RainbowTopHighlight(shape: cubeShape, strength: 0.55))
                .rainbowGlow(RainbowPalette.focusBlue, radius: 4)

        case .blocked:
            cubeShape
                .fill(RainbowPalette.actionOrange.soft)
                .overlay {
                    // Shape axis: pause bars in ink.
                    HStack(spacing: size * 0.14) {
                        barShape.frame(width: size * 0.14, height: size * 0.46)
                        barShape.frame(width: size * 0.14, height: size * 0.46)
                    }
                }
                .overlay(cubeShape.strokeBorder(
                    RainbowPalette.actionOrange.ink.opacity(increaseContrast ? 1 : 0.9),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                ))

        case .closed:
            cubeShape
                .fill(RainbowPalette.growthGreen.base)
                .overlay(litFromAbove)
                .overlay {
                    // Shape axis: the white check, snapping in with a
                    // squish on live transitions (static when the view
                    // first appears already-closed, so snapshots and
                    // scrolled-in rows render settled).
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.4).combined(with: .opacity))
                }
                .overlay(RainbowTopHighlight(shape: cubeShape, strength: 0.55))
                .rainbowGlow(RainbowPalette.growthGreen, radius: 4)
        }
    }

    /// Raised-empty fill for the todo cube: white→mist top-lit gradient
    /// (charcoal equivalents in dark mode).
    private var emptyGradient: LinearGradient {
        LinearGradient(
            colors: [
                RainbowPalette.dynamic(light: 0xFFFFFF, dark: 0x262833),
                RainbowPalette.dynamic(light: 0xEEF0F5, dark: 0x1F2128),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Subtle white wash from the top edge that makes a filled cube
    /// read as a lit, volumetric object instead of a flat swatch.
    private var litFromAbove: some View {
        cubeShape.fill(
            LinearGradient(
                colors: [.white.opacity(0.28), .white.opacity(0)],
                startPoint: .top, endPoint: .center
            )
        )
        .allowsHitTesting(false)
    }

    private var barShape: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(RainbowPalette.actionOrange.ink)
    }
}
