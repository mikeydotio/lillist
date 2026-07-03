import SwiftUI

import LillistCore

/// The status control for a widget task row: the app's own `StatusCubeView`
/// chip (identical multi-step todo → started → blocked → done visual) plus a
/// VoiceOver label (the chip itself is purely visual — its accessibility lives
/// in `StatusIndicatorView`, which the widget can't use because it relies on a
/// `Menu`). The widget extension wraps this in a `Button(intent:)` for
/// tap-to-cycle; the row convenience initializer, previews, and snapshot tests
/// render it non-interactively.
public struct WidgetStatusChip: View {
    public var status: Status

    public init(status: Status) {
        self.status = status
    }

    public var body: some View {
        StatusCubeView(status: status)
            .accessibilityLabel(Text(StatusGlyph.accessibilityLabel(for: status)))
    }
}

/// A single task row: leading status chip + one-line, tail-truncated title.
/// `Leading` is injected so the widget extension can supply an interactive
/// `Button(intent:)`-wrapped ``WidgetStatusChip``; the convenience initializer
/// renders the plain chip for previews and snapshot tests.
///
/// `titleURL`, when set, wraps the title (and the trailing space that fills the
/// row) in a `Link` so tapping the row opens that task — a distinct tap target
/// from the leading status glyph.
public struct WidgetTaskRowView<Leading: View>: View {
    private let row: WidgetSnapshot.Row
    private let titleURL: URL?
    private let leading: Leading

    public init(row: WidgetSnapshot.Row, titleURL: URL? = nil, @ViewBuilder leading: () -> Leading) {
        self.row = row
        self.titleURL = titleURL
        self.leading = leading()
    }

    public var body: some View {
        HStack(spacing: LillistSpacing.m) {
            leading
            if let titleURL {
                Link(destination: titleURL) { titleContent }
            } else {
                titleContent
            }
        }
    }

    private var titleContent: some View {
        // Same spacing the original flat row used between the title and the
        // trailing spacer, so wrapping the title in a Link is visually a no-op.
        HStack(spacing: LillistSpacing.m) {
            Text(row.title)
                .font(LillistTypography.body)
                .foregroundStyle(row.status.isClosed ? LillistColor.textFaint : LillistColor.textStrong)
                .strikethrough(row.status.isClosed, color: LillistColor.textFaint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}

extension WidgetTaskRowView where Leading == WidgetStatusChip {
    /// Non-interactive convenience: renders the plain status chip.
    public init(row: WidgetSnapshot.Row, titleURL: URL? = nil) {
        self.init(row: row, titleURL: titleURL) { WidgetStatusChip(status: row.status) }
    }
}
