import SwiftUI

/// A non-interactive path breadcrumb (`A › B › C`). Today every
/// segment is plain `Text`; the whole stack composes one
/// accessibility element with the path read aloud.
///
/// # MARK: Accessibility
///
/// When segments become tappable (a future plan moves breadcrumbs
/// to navigation), the contract changes:
///
/// 1. Each segment becomes a `Button { … } label: { Text(name) }`
///    with `.accessibilityAddTraits(.isButton)` so VoiceOver
///    announces "Button: A".
/// 2. The outer `.accessibilityElement(children: .combine)` becomes
///    `.contain` (or is removed) so each button keeps its own
///    focus identity.
/// 3. The container `.accessibilityLabel("Path: …")` becomes
///    `.accessibilityLabel("Path")` so the path isn't read twice.
///
/// Until then, the combined-element + composed-label pattern is the
/// correct read-only contract.
public struct BreadcrumbView: View {
    public var path: [String]
    public init(path: [String]) { self.path = path }
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(path.enumerated()), id: \.offset) { i, name in
                if i > 0 { Image(systemName: "chevron.forward").font(.caption2).foregroundStyle(LillistColor.textFaint) }
                Text(name)
                    .font(i == path.count - 1 ? LillistTypography.caption : LillistTypography.caption2)
                    .foregroundStyle(i == path.count - 1 ? LillistColor.textStrong : LillistColor.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            let joined = path.joined(separator: " › ")
            return String(localized: "Path: \(joined)", bundle: .module)
        }())
    }
}
