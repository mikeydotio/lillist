import SwiftUI

public struct SidebarRowView: View {
    public enum Kind: Sendable { case task, smartFilter, tag, trash }
    public var icon: String
    public var label: String
    public var badge: Int?
    public var tint: TagTint?
    public var kind: Kind

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    public init(icon: String, label: String, badge: Int? = nil, tint: TagTint? = nil, kind: Kind) {
        self.icon = icon
        self.label = label
        self.badge = badge
        self.tint = tint
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: LillistSpacing.s) {
            Image(systemName: icon)
                .foregroundStyle(tint?.resolved(in: scheme).color ?? .accentColor)
                .frame(width: 18)
            Text(label).lineLimit(1)
            Spacer()
            if let badge, badge > 0 {
                badgeView(count: badge)
            }
        }
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
                .background(Capsule().fill(.quaternary))
                .accessibilityLabel(String(localized: "\(count) items", bundle: .module))
        }
    }
}
