import SwiftUI

import LillistCore

/// The status glyph for a widget task row: an empty circle for `todo` (matching
/// the design mock), and status-tinted glyphs otherwise. Pure visual — the
/// widget extension wraps this in a `Button(intent:)` for tap-to-complete
/// (WidgetKit interactivity can't live in LillistUI, which never imports it).
public struct WidgetCheckGlyph: View {
    public var status: Status
    /// Point size of the glyph. Scales with the row's font by default.
    public var size: CGFloat

    public init(status: Status, size: CGFloat = 18) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size))
            .foregroundStyle(StatusPalette.color(for: status))
            .accessibilityLabel(Text(StatusGlyph.accessibilityLabel(for: status)))
    }

    private var symbolName: String {
        switch status {
        case .todo: "circle"
        case .started: "circle.inset.filled"
        case .blocked: "circle.dashed"
        case .closed: "checkmark.circle.fill"
        }
    }
}

/// A single task row: leading status glyph + one-line, tail-truncated title.
/// `Leading` is injected so the widget extension can supply an interactive
/// `Button(intent:)`-wrapped ``WidgetCheckGlyph``; the convenience initializer
/// renders the plain glyph for previews and snapshot tests.
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

extension WidgetTaskRowView where Leading == WidgetCheckGlyph {
    /// Non-interactive convenience: renders the plain status glyph.
    public init(row: WidgetSnapshot.Row, titleURL: URL? = nil) {
        self.init(row: row, titleURL: titleURL) { WidgetCheckGlyph(status: row.status) }
    }
}
