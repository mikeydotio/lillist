import SwiftUI

/// Rainbow Logic empty state: the app icon's faint dot-grid texture,
/// a spectrum-masked SF Symbol, headline + message, and an optional
/// CTA slot. Replaces `ContentUnavailableView` on themed surfaces —
/// empty states and heroes are the *only* places the dot grid
/// appears (design-system rule).
public struct RainbowEmptyStateView<Actions: View>: View {
    public var title: String
    public var message: String
    public var systemImage: String
    @ViewBuilder public var actions: () -> Actions

    public init(
        title: String,
        message: String,
        systemImage: String,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(RainbowGradient.vertical)
                .accessibilityHidden(true)

            VStack(spacing: LillistSpacing.s) {
                Text(title)
                    .font(LillistTypography.title2)
                    .foregroundStyle(LillistColor.textStrong)
                Text(message)
                    .font(LillistTypography.subheadline)
                    .foregroundStyle(LillistColor.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            actions()
                .padding(.top, LillistSpacing.xs)
        }
        .padding(LillistSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGridBackdrop())
        .background(LillistColor.workspace)
    }
}

/// The icon's dotted-grid texture: 22 pt pitch, 1.3 pt dots, near-
/// invisible ink. Drawn once into a `Canvas` and rasterized via
/// `drawingGroup` so scrolling/resizing never re-runs the loop.
/// Public so app-target hero surfaces (onboarding) can use it; the
/// design-system rule stands — heroes and empty states only.
public struct DotGridBackdrop: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 22
            let radius: CGFloat = 1.3
            let color = Color.primary.opacity(0.055)
            var y: CGFloat = pitch / 2
            while y < size.height {
                var x: CGFloat = pitch / 2
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(color)
                    )
                    x += pitch
                }
                y += pitch
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
