import SwiftUI

public struct SidebarRowView: View {
    public enum Kind: Sendable { case task, smartFilter, tag, trash }
    public var icon: String
    public var label: String
    public var badge: Int?
    public var tint: TagTint?
    public var kind: Kind
    /// Drives the Rainbow icon-chip fill. The *row* selection pill
    /// stays the system's (NavigationSplitView sidebar); this only
    /// paints the chip. Default false so existing callers compile.
    public var isSelected: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    public init(
        icon: String, label: String, badge: Int? = nil,
        tint: TagTint? = nil, kind: Kind, isSelected: Bool = false
    ) {
        self.icon = icon
        self.label = label
        self.badge = badge
        self.tint = tint
        self.kind = kind
        self.isSelected = isSelected
    }

    private var chipColor: Color {
        tint?.resolved(in: scheme).color ?? .accentColor
    }

    public var body: some View {
        HStack(spacing: LillistSpacing.s) {
            // Rainbow Logic icon chip: tinted glyph at rest; the chip
            // fills with the functional/tag color (white glyph + top
            // highlight) when the row is selected.
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                        .fill(chipColor)
                        .overlay(RainbowTopHighlight(
                            shape: RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous),
                            strength: 0.4
                        ))
                }
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : chipColor)
            }
            .frame(width: 22, height: 22)
            Text(label).lineLimit(1)
            Spacer()
            if let badge, badge > 0 {
                badgeView(count: badge)
            }
        }
        // MARK: Accessibility
        // The .accessibilityElement(children: .combine) + .accessibilityLabel
        // pair runs *last* in the body chain so the row's selection-tag
        // (applied by SidebarView consumers via .tag(SidebarSelection.…))
        // doesn't mask the explicit label. The
        // SidebarRowViewA11yTests.test_rowExposesAccessibilityLabel_whenComposedWithTag
        // regression test pins the ordering.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge.map {
            String(localized: "\(label), \($0) items", bundle: .module)
        } ?? label)
    }

    @ViewBuilder
    private func badgeView(count: Int) -> some View {
        let increaseContrast = overrideIncreaseContrast ?? systemIncreaseContrast
        let label = Text("\(count)")
            .font(LillistTypography.caption2)
            .padding(.horizontal, LillistSpacing.xs + 2)
            .padding(.vertical, 1)

        if increaseContrast {
            label
                .foregroundStyle(.primary)
                .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.8), lineWidth: 0.5))
                .accessibilityLabel(String(localized: "\(count) items", bundle: .module))
        } else {
            label
                .monospacedDigit()
                .foregroundStyle(LillistColor.textFaint)
                .accessibilityLabel(String(localized: "\(count) items", bundle: .module))
        }
    }
}
