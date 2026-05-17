import SwiftUI

public struct TagChipView: View {
    public var name: String
    public var tint: TagTint?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    public init(name: String, tint: TagTint? = nil) {
        self.name = name
        self.tint = tint
    }

    public var body: some View {
        let increaseContrast = overrideIncreaseContrast ?? systemIncreaseContrast
        let resolved = tint?.resolved(in: scheme)
        let base = (resolved?.color ?? .gray)
        Text(name)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(base.opacity(increaseContrast ? 0.30 : 0.18))
            )
            .foregroundStyle(
                increaseContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(resolved?.color ?? .secondary)
            )
            .overlay(
                Capsule().stroke(base.opacity(increaseContrast ? 0.85 : 0.45),
                                 lineWidth: increaseContrast ? 1.0 : 0.5)
            )
            .accessibilityLabel(String(localized: "Tag: \(name)", bundle: .module))
    }
}
