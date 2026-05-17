import SwiftUI

/// Empty-state placeholder for surfaces that have no content yet.
///
/// **Platform scope:** macOS-only as of Plan 18. iOS surfaces should
/// use the system `ContentUnavailableView` (iOS 17+), which is the
/// established convention across `AllTagsView`, `TaskDetailView`, and
/// the iOS list shells. Compiling on iOS is permitted (the snapshot
/// tour fixtures need it on iOS for visual parity in screenshots) but
/// new iOS callers should prefer `ContentUnavailableView`.
///
/// Plan 14 Task 4 migrated the component to design tokens; Plan 18
/// Task 8 made the platform scope explicit. If/when macOS adopts
/// `ContentUnavailableView` too (separate design call), this view can
/// be retired.
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
