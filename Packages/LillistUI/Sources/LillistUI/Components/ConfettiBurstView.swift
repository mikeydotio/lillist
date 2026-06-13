import SwiftUI
import LillistCore

/// Decides whether a status transition earns the rainbow confetti
/// burst — the brand's completion moment. Pure logic, separated from
/// the view so the transition × Reduce-Motion matrix is unit-testable
/// (`ConfettiPolicyTests`).
public enum ConfettiPolicy {
    /// Burst only on a transition *into* `.closed` (re-closing an
    /// already-closed task or any other transition stays quiet), and
    /// never under Reduce Motion.
    public nonisolated static func shouldBurst(
        from old: Status, to new: Status, reduceMotion: Bool
    ) -> Bool {
        !reduceMotion && old != .closed && new == .closed
    }
}

/// One-shot rainbow confetti burst: ten small rounded quads cycling
/// the six spectrum stops, flying outward over 600 ms with an
/// ease-out, fading and spinning as they go.
///
/// Implementation notes (these are contracts, not trivia):
/// - **Deterministic geometry.** Particle angles/distances/spins come
///   from a fixed-seed SplitMix64, so any render at a given elapsed
///   time is reproducible. No `Math.random()`-style drift between
///   record and verify renders.
/// - **Snapshot-safe by construction.** The view exists only while a
///   live transition's 650 ms window is open (the parent removes it —
///   see `StatusCubeView`); static fixtures can never contain one.
/// - **No timers.** `TimelineView(.animation)` drives frames and
///   pauses itself once the burst completes; cleanup is the parent's
///   structured `.task`, which cancels with the view.
public struct ConfettiBurstView: View {
    /// Wall-clock birth of the burst; drives elapsed time.
    private let start = Date()

    private static let life: TimeInterval = 0.6
    private static let particleCount = 10

    private struct Particle {
        let direction: CGVector
        let distance: CGFloat
        let spin: Angle
        let color: Color
    }

    private static let particles: [Particle] = {
        var rng = SplitMix64(seed: 0x5EED_C0DE_CAFE_F00D)
        return (0 ..< particleCount).map { i in
            let angle = (2 * .pi * Double(i)) / Double(particleCount) + rng.unitDouble()
            let distance = 18 + rng.unitDouble() * 14
            return Particle(
                direction: CGVector(dx: cos(angle), dy: sin(angle)),
                distance: distance,
                spin: .degrees(rng.unitDouble() * 360),
                color: RainbowPalette.Spectrum.stops[i % RainbowPalette.Spectrum.stops.count]
            )
        }
    }()

    public init() {}

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: false)) { context in
            Canvas { canvas, size in
                let elapsed = context.date.timeIntervalSince(start)
                let t = min(max(elapsed / Self.life, 0), 1)
                guard t < 1 else { return }
                // Ease-out: fast launch, gentle landing.
                let eased = 1 - pow(1 - t, 3)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for particle in Self.particles {
                    var ctx = canvas
                    ctx.translateBy(
                        x: center.x + particle.direction.dx * particle.distance * eased,
                        y: center.y + particle.direction.dy * particle.distance * eased
                    )
                    ctx.rotate(by: particle.spin * t)
                    ctx.opacity = 1 - t
                    ctx.fill(
                        Path(roundedRect: CGRect(x: -3.5, y: -3.5, width: 7, height: 7), cornerRadius: 2),
                        with: .color(particle.color)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Tiny deterministic RNG (SplitMix64). Good enough scatter for
/// confetti jitter; chosen for its two-line implementation and stable
/// output across platforms/processes.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in [0, 1).
    mutating func unitDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
