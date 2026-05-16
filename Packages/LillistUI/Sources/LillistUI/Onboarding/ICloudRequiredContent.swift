import SwiftUI

/// Shared body content for the "iCloud is required" full-screen
/// blocker. Renders the heading, descriptive copy, and an optional
/// error line. The action bar (Open Settings + Try again) lives in
/// the per-platform wrapper because the destination URLs and button
/// styling differ.
///
/// Plan 14 lifted this from the iOS `ICloudRequiredScreen` and macOS
/// `ICloudRequiredView`, which had drifted in wording and font
/// treatment.
public struct ICloudRequiredContent: View {
    public var lastError: String?

    public init(lastError: String? = nil) {
        self.lastError = lastError
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Image(systemName: "icloud.slash")
                .font(LillistTypography.largeTitle.weight(.light))
                .foregroundStyle(.red)
            Text("iCloud is required")
                .font(LillistTypography.title.weight(.bold))
            Text("Lillist syncs your tasks via your private iCloud database. Sign into iCloud in Settings, then return here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if let lastError {
                Text(lastError)
                    .font(LillistTypography.body)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 420)
            }
        }
    }
}
