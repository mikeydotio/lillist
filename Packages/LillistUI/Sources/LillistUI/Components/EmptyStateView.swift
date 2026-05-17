import SwiftUI

public struct EmptyStateView: View {
    public var title: String
    public var message: String
    public var systemImage: String

    @FocusState private var focused: Bool

    public init(title: String, message: String, systemImage: String = "tray") {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.s + 2) {
            Image(systemName: systemImage)
                .font(LillistTypography.largeTitle.weight(.light))
                .foregroundStyle(.tertiary)
            Text(title).font(LillistTypography.headline)
            Text(message)
                .font(LillistTypography.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .focusable()
        .focused($focused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(title). \(message)", bundle: .module))
        .accessibilityAddTraits(.isStaticText)
    }
}
