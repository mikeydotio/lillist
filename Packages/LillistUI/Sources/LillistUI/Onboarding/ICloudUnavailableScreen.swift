import SwiftUI

/// Plan 21: first-launch informational screen shown when iCloud is
/// unavailable. Replaces the old `ICloudRequiredScreen` /
/// `ICloudRequiredView` blocker — the app is no longer gated behind
/// iCloud. The user taps "Continue" to drop into LocalOnly onboarding.
///
/// The screen is pure presentation: layout + copy + a single action
/// closure. The host wires `onContinue` to the
/// `OnboardingPresentationModifier` to advance state.
public struct ICloudUnavailableScreen: View {
    public let onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Spacer()

            Image(systemName: "icloud.slash")
                .font(LillistTypography.largeTitle.weight(.medium))
                .foregroundStyle(RainbowPalette.cautionAmber.ink)
                .accessibilityHidden(true)

            Text("iCloud Unavailable")
                .font(LillistTypography.title)
                .foregroundStyle(LillistColor.textStrong)
                .accessibilityAddTraits(.isHeader)

            Text("Lillist works locally on this device without iCloud. Your tasks, tags, and reminders stay here unless you turn on iCloud Sync later in Settings.")
                .font(LillistTypography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(LillistColor.textMuted)
                .frame(maxWidth: 420)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.rainbow(.lavender))
            .padding(.bottom, LillistSpacing.l)
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGridBackdrop())
        .background(LillistColor.workspace)
    }
}
