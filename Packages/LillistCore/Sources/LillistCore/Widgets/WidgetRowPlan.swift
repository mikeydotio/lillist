import Foundation

/// `LIL-95`: the shared truncation pass applied at both places a widget row
/// list gets capped — ``WidgetSnapshotBuilder`` capping the persisted
/// snapshot at `rowCap`, and the card view capping again at a family's
/// `WidgetLayout.maxRows`. One implementation so the two cap points can't
/// drift apart on the stranded-context-row rule.
public enum WidgetRowPlan {
    /// One row as it should actually render. `showsParentMarker` is always
    /// computed fresh against the final visible set — it can't be persisted
    /// on `Row` because visibility depends on the family's own `limit`, which
    /// the snapshot doesn't know about.
    public struct Item: Sendable, Equatable, Identifiable {
        public let row: WidgetSnapshot.Row
        public let depth: Int
        public let showsParentMarker: Bool

        public var id: UUID { row.id }

        public init(row: WidgetSnapshot.Row, depth: Int, showsParentMarker: Bool) {
            self.row = row
            self.depth = depth
            self.showsParentMarker = showsParentMarker
        }
    }

    /// - Parameter rows: a tree already flattened depth-first (parent
    ///   immediately followed by all its descendants) — the shape
    ///   ``WidgetSnapshotBuilder``'s tree-shaping step produces. This is not
    ///   re-validated; a caller handing in an arbitrary order gets an
    ///   arbitrarily wrong `showsParentMarker` result.
    /// - Parameter limit: maximum rows to keep, applied before markers are
    ///   computed so a row cut by the limit can never satisfy someone else's
    ///   visibility.
    public static func plan(rows: [WidgetSnapshot.Row], limit: Int) -> [Item] {
        var capped = Array(rows.prefix(max(0, limit)))

        // A truncation that lands exactly on a context row strands it —
        // every reason it was on the card (its children) got cut. Only the
        // TAIL can strand this way: depth-first order emits a parent
        // immediately before its descendants, so a context row surviving the
        // cap with none of its children means it was the very last thing
        // `prefix` kept. A chain of stranded context rows unwinds in one pass.
        while let last = capped.last, last.isContext {
            capped.removeLast()
        }

        let visibleIDs = Set(capped.map(\.id))
        return capped.map { row in
            let marker = !row.isContext && row.parentID != nil && !visibleIDs.contains(row.parentID!)
            return Item(row: row, depth: row.depth, showsParentMarker: marker)
        }
    }
}
