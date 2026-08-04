import Foundation

/// `LIL-95`: the shared truncation/re-leveling pass applied at both places a
/// widget row list gets capped — ``WidgetSnapshotBuilder`` capping the
/// persisted snapshot at `rowCap`, and the card view capping again at a
/// family's `WidgetLayout.maxRows`. One implementation so the two cap points
/// can't drift apart on the stranded-context-row and re-leveling rules.
public enum WidgetRowPlan {
    /// One row as it should actually render: `depth` may differ from
    /// `row.depth` (re-levelled when context rows are dropped), and
    /// `showsParentMarker` is always computed fresh against the final
    /// visible set — it can't be persisted on `Row` because visibility
    /// depends on the family's limit and `allowsContextRows`, neither of
    /// which the snapshot knows about.
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
    ///   re-validated; a caller handing in an arbitrary order gets
    ///   arbitrarily wrong re-leveling and marker results.
    /// - Parameter limit: maximum rows to keep, applied before markers are
    ///   computed so a row cut by the limit can never satisfy someone else's
    ///   visibility.
    /// - Parameter allowsContextRows: when `false`, every `isContext` row is
    ///   dropped and its surviving descendants re-level: a descendant whose
    ///   immediate parent survived (as a member) keeps its relative nesting;
    ///   a descendant whose immediate parent was a now-dropped context row
    ///   flattens fully to root, not to some visible grandparent — the same
    ///   "parent not shown" rule that drives `showsParentMarker`.
    public static func plan(
        rows: [WidgetSnapshot.Row],
        limit: Int,
        allowsContextRows: Bool
    ) -> [Item] {
        let leveled: [(row: WidgetSnapshot.Row, depth: Int)]
        if allowsContextRows {
            leveled = rows.map { ($0, $0.depth) }
        } else {
            var newDepthByID: [UUID: Int] = [:]
            var kept: [(row: WidgetSnapshot.Row, depth: Int)] = []
            kept.reserveCapacity(rows.count)
            for row in rows where !row.isContext {
                let depth: Int
                if let parentID = row.parentID, let parentDepth = newDepthByID[parentID] {
                    depth = min(parentDepth + 1, 2)
                } else {
                    depth = 0
                }
                newDepthByID[row.id] = depth
                kept.append((row, depth))
            }
            leveled = kept
        }

        var capped = Array(leveled.prefix(max(0, limit)))

        // A truncation that lands exactly on a context row strands it —
        // every reason it was on the card (its children) got cut. Only the
        // TAIL can strand this way: depth-first order emits a parent
        // immediately before its descendants, so a context row surviving the
        // cap with none of its children means it was the very last thing
        // `prefix` kept. A chain of stranded context rows unwinds in one pass.
        while let last = capped.last, last.row.isContext {
            capped.removeLast()
        }

        let visibleIDs = Set(capped.map { $0.row.id })
        return capped.map { entry in
            let marker = !entry.row.isContext
                && entry.row.parentID != nil
                && !visibleIDs.contains(entry.row.parentID!)
            return Item(row: entry.row, depth: entry.depth, showsParentMarker: marker)
        }
    }
}
