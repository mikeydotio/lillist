import SwiftUI

public struct SidebarRowView: View {
    public enum Kind: Sendable { case task, smartFilter, tag, trash }
    public var icon: String
    public var label: String
    public var badge: Int?
    public var tint: TagTint?
    public var kind: Kind

    @Environment(\.colorScheme) private var scheme

    public init(icon: String, label: String, badge: Int? = nil, tint: TagTint? = nil, kind: Kind) {
        self.icon = icon
        self.label = label
        self.badge = badge
        self.tint = tint
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint?.resolved(in: scheme).color ?? .accentColor)
                .frame(width: 18)
            Text(label).lineLimit(1)
            Spacer()
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
                    .accessibilityLabel("\(badge) items")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge.map { "\(label), \($0) items" } ?? label)
    }
}
