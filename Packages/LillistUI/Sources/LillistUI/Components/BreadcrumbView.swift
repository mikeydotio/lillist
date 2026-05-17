import SwiftUI

public struct BreadcrumbView: View {
    public var path: [String]
    public init(path: [String]) { self.path = path }
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(path.enumerated()), id: \.offset) { i, name in
                if i > 0 { Image(systemName: "chevron.forward").font(.caption2).foregroundStyle(.tertiary) }
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            let joined = path.joined(separator: " › ")
            return String(localized: "Path: \(joined)", bundle: .module)
        }())
    }
}
