import SwiftUI

/// Small, muted "marketing-version (build)" footer used under the
/// primary task list on each platform. Centered horizontally; uses
/// `LillistTypography.caption2` so the label respects Dynamic Type
/// like the rest of the chrome.
public struct BuildVersionLabel: View {
    public var version: String

    public init(version: String) {
        self.version = version
    }

    public var body: some View {
        Text(version)
            .font(LillistTypography.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LillistSpacing.xs)
            .accessibilityLabel(Text(String(localized: "App version \(version)", bundle: .module)))
    }
}

#Preview {
    BuildVersionLabel(version: "0.1.0 (16)")
}
