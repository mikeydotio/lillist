import SwiftUI
import LillistCore

/// The Rainbow Glass status chip — the visual heart of a task row.
///
/// A **solid tinted circular chip** with a **shape axis** independent of
/// hue so status stays legible for colorblind users and under
/// differentiate-without-color:
///
/// | status  | fill              | shape                          |
/// |---------|-------------------|--------------------------------|
/// | todo    | neutral + stroke  | empty chip                     |
/// | started | focus-blue        | white leading half             |
/// | blocked | action-orange soft| dashed ink border + pause bars |
/// | closed  | growth-green      | white check (squish snap)      |
///
/// Rainbow Glass reserves the real Liquid Glass material for the
/// *floating control layer* (FAB, toasts, panels, the filter header);
/// per-row content like this chip stays a flat tinted solid — that's
/// Apple's guidance, and it keeps the chip cheap on long lists and
/// snapshot-testable in the standard suite. The old faux-volume
/// (emptyGradient, litFromAbove, top highlight, hue glow, isometric
/// cube) is retired; this is a clean circular tint.
///
/// Purely visual: tap-to-cycle, the explicit-setter menu, hit targets,
/// and every accessibility attribute live in `StatusIndicatorView`,
/// which renders this view as its `Menu` label. The chip also hosts the
/// one-shot confetti burst on a transition into `.closed`
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

    private var increaseContrast: Bool {
        overrideIncreaseContrast ?? systemIncreaseContrast
    }

    private var reduceMotion: Bool {
        overrideReduceMotion ?? systemReduceMotion
    }

    public var body: some View {
        chip
            .frame(width: size, height: size)
            .overlay {
                if burstID != nil {
                    ConfettiBurstView()
                        // Particles fly past the chip's bounds.
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
    private var chip: some View {
        switch status {
        case .todo:
            Circle()
                .fill(LillistColor.card)
                .overlay(Circle().strokeBorder(
                    increaseContrast ? LillistColor.borderStrong : LillistColor.borderSoft,
                    lineWidth: 1
                ))

        case .started:
            Circle()
                .fill(RainbowPalette.focusBlue.base)
                .overlay {
                    // Shape axis: leading half filled white, clipped to
                    // the chip circle.
                    HStack(spacing: 0) {
                        Rectangle().fill(.white).opacity(0.9)
                        Color.clear
                    }
                    .clipShape(Circle())
                }

        case .blocked:
            Circle()
                .fill(RainbowPalette.actionOrange.soft)
                .overlay {
                    // Shape axis: pause bars in ink.
                    HStack(spacing: size * 0.14) {
                        barShape.frame(width: size * 0.14, height: size * 0.46)
                        barShape.frame(width: size * 0.14, height: size * 0.46)
                    }
                }
                .overlay(Circle().strokeBorder(
                    RainbowPalette.actionOrange.ink.opacity(increaseContrast ? 1 : 0.9),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                ))

        case .closed:
            Circle()
                .fill(RainbowPalette.growthGreen.base)
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
        }
    }

    private var barShape: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(RainbowPalette.actionOrange.ink)
    }
}
