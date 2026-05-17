import SwiftUI

public struct TagChipView: View {
    public var name: String
    public var tint: TagTint?
    @Environment(\.colorScheme) private var scheme

    public init(name: String, tint: TagTint? = nil) {
        self.name = name
        self.tint = tint
    }

    public var body: some View {
        let resolved = tint?.resolved(in: scheme)
        Text(name)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill((resolved?.color ?? .gray).opacity(0.18))
            )
            .foregroundStyle(resolved?.color ?? .secondary)
            .overlay(
                Capsule().stroke((resolved?.color ?? .gray).opacity(0.45), lineWidth: 0.5)
            )
            .accessibilityLabel(String(localized: "Tag: \(name)", bundle: .module))
    }
}
