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

/// A single task row: leading indent gutter (`depth`) + status chip +
/// one-line, tail-truncated title, optionally preceded by a faint "parent not
/// shown here" marker. `Leading` is injected so the widget extension can
/// supply an interactive `Button(intent:)`-wrapped ``WidgetStatusChip``; the
/// convenience initializer renders the plain chip for previews and snapshot
/// tests.
///
/// `titleURL`, when set, wraps the title (and the trailing space that fills the
/// row) in a `Link` so tapping the row opens that task — a distinct tap target
/// from the leading status glyph.
public struct WidgetTaskRowView<Leading: View>: View {
    private let row: WidgetSnapshot.Row
    private let titleURL: URL?
    private let depth: Int
    private let showsParentMarker: Bool
    private let indentPerLevel: CGFloat
    private let leading: Leading

    /// - Parameter depth: nesting tier (from ``WidgetRowPlan/Item``), rendered
    ///   as a leading indent — `0` (the default) renders exactly as before
    ///   `LIL-95`, byte-identical to every pre-existing snapshot baseline.
    /// - Parameter showsParentMarker: `true` when this task's true parent
    ///   exists but isn't rendered on the card — a faint, untappable triangle
    ///   before the title, the only signal that this row's context is
    ///   incomplete (small-family orphans, or a lookup that couldn't resolve
    ///   the parent).
    public init(
        row: WidgetSnapshot.Row,
        titleURL: URL? = nil,
        depth: Int = 0,
        showsParentMarker: Bool = false,
        indentPerLevel: CGFloat = LillistSpacing.m,
        @ViewBuilder leading: () -> Leading
    ) {
        self.row = row
        self.titleURL = titleURL
        self.depth = depth
        self.showsParentMarker = showsParentMarker
        self.indentPerLevel = indentPerLevel
        self.leading = leading()
    }

    public var body: some View {
        HStack(spacing: LillistSpacing.m) {
            if depth > 0 {
                // `height: 0` matters: `Color.clear.frame(width:)` alone has
                // no intrinsic height, so it greedily expands to fill all
                // available vertical space — fine inside a `List` (each row
                // sizes independently there), but this card is a plain
                // `VStack` with a trailing `Spacer`, where a single greedy
                // child inflates its own row and shoves every row below it
                // down. Pinning height to 0 keeps this a pure width spacer.
                Color.clear.frame(width: CGFloat(depth) * indentPerLevel, height: 0)
            }
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
            HStack(spacing: LillistSpacing.xs) {
                if showsParentMarker {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(LillistColor.textFaint)
                        .accessibilityHidden(true)
                }
                Text(row.title)
                    .font(LillistTypography.body)
                    .foregroundStyle(row.status.isClosed ? LillistColor.textFaint : LillistColor.textStrong)
                    .strikethrough(row.status.isClosed, color: LillistColor.textFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }
}

extension WidgetTaskRowView where Leading == WidgetStatusChip {
    /// Non-interactive convenience: renders the plain status chip.
    public init(
        row: WidgetSnapshot.Row,
        titleURL: URL? = nil,
        depth: Int = 0,
        showsParentMarker: Bool = false,
        indentPerLevel: CGFloat = LillistSpacing.m
    ) {
        self.init(
            row: row,
            titleURL: titleURL,
            depth: depth,
            showsParentMarker: showsParentMarker,
            indentPerLevel: indentPerLevel
        ) { WidgetStatusChip(status: row.status) }
    }
}
