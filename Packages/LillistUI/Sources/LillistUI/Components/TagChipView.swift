import SwiftUI

/// A pill-shaped tag chip. Today pure-text, non-interactive.
///
/// # MARK: When tappable
///
/// When `onRemove: (() -> Void)?` becomes a parameter (planned for
/// the tag-editor surface), the contract changes:
///
/// 1. The chip becomes `Button { onRemove?() } label: { … }` (or
///    adds an inline "x" button to the right of the text).
/// 2. Add `.accessibilityAddTraits(.isButton)` so VoiceOver
///    announces "Button: Tag: work".
/// 3. Add `.accessibilityAction(named: "Remove") { onRemove?() }`
///    so Switch Control / Voice Control / VoiceOver users can
///    invoke removal without performing the visual "x" tap.
///
/// Until then, the read-only `Text` + `.accessibilityLabel("Tag: …")`
/// pattern is the correct contract.
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
