#if DEBUG
import SwiftUI

/// **Wave 0 spike — delete after the Wave 3 go/no-go.**
///
/// Apple's guidance keeps Liquid Glass on the floating control layer and
/// off repeating content. Rainbow Glass deliberately pushes further, so
/// this harness exists to make that bet evidence-based: it renders the
/// two candidate task-row treatments at list scale so the decision can be
/// made on what actually renders, not on theory.
///
/// **How to use:**
///   1. Open the previews below on an iOS 26 / macOS 26 canvas, in light
///      and dark, with Reduce Transparency and Increase Contrast toggled
///      (Xcode canvas variants). Judge title/meta legibility over the
///      scrolling content beneath each glass row.
///   2. Scroll-perf is the other half and needs hardware: run the
///      `.fullGlass` variant on-device with Instruments' Animation Hitches
///      / Core Animation FPS template on a 200+ row list. Per-row glass is
///      a real render cost — this is the analogue of the existing
///      "rows cap at `.xs`" performance rule.
///
/// **Decision:** if `.fullGlass` stays legible *and* holds frame rate,
/// Wave 3 glassifies rows. Otherwise Wave 3 ships `.accentGlass`
/// (opaque tinted card + glass only on the status element/controls),
/// which still retires the hand-rolled shadow without the per-row cost.
struct GlassRowSpike: View {
    enum Variant: String, CaseIterable, Identifiable {
        /// The whole row is a glass card surface.
        case fullGlass = "Full glass rows"
        /// Opaque card; glass only on the status accent.
        case accentGlass = "Accent glass only"
        var id: String { rawValue }
    }

    @State private var variant: Variant = .fullGlass

    private static let hues: [Color] = [
        RainbowPalette.focusBlue.base,
        RainbowPalette.actionOrange.base,
        RainbowPalette.growthGreen.base,
        RainbowPalette.scriptPurple.base,
        RainbowPalette.cautionAmber.base,
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Variant", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(LillistSpacing.m)

            ScrollView {
                LazyVStack(spacing: LillistSpacing.s) {
                    ForEach(0..<60, id: \.self) { index in
                        row(index: index, hue: Self.hues[index % Self.hues.count])
                    }
                }
                .padding(.horizontal, LillistSpacing.l)
                .padding(.bottom, LillistSpacing.xxl)
            }
        }
        // A rainbow wash *behind* the list, so glass rows have something
        // worth refracting (mirrors a real populated workspace).
        .background(RainbowGradient.vertical.opacity(0.18).ignoresSafeArea())
    }

    @ViewBuilder
    private func row(index: Int, hue: Color) -> some View {
        let content = HStack(spacing: LillistSpacing.m) {
            // Status accent — always glass, tinted by the functional hue.
            Circle()
                .fill(.clear)
                .frame(width: 26, height: 26)
                .glassSurface(.statusTinted(hue), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Spike task \(index + 1) — legibility probe")
                    .font(LillistTypography.headline)
                    .foregroundStyle(LillistColor.textStrong)
                Text("Due tomorrow · #project · refracting the content below")
                    .font(LillistTypography.caption)
                    .foregroundStyle(LillistColor.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(LillistSpacing.m)

        switch variant {
        case .fullGlass:
            content.glassSurface(.card, in: RoundedRectangle(cornerRadius: LillistRadius.m, style: .continuous))
        case .accentGlass:
            content.background(
                LillistColor.card,
                in: RoundedRectangle(cornerRadius: LillistRadius.m, style: .continuous)
            )
        }
    }
}

#Preview("Glass rows — light") {
    GlassRowSpike()
}

#Preview("Glass rows — dark") {
    GlassRowSpike()
        .preferredColorScheme(.dark)
}
#endif
