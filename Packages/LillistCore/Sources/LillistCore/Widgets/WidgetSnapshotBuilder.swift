import Foundation

/// Produces ``WidgetSnapshot`` JSON for the widget extension from the live
/// stores. Runs in the app (or a writing extension) whenever task/filter data
/// changes; the widget only ever *reads* the result.
///
/// **Pure LillistCore — no WidgetKit.** The `WidgetCenter.reloadTimelines(...)`
/// call that follows a regeneration lives in the app/extension target (e.g.
/// `WidgetRefreshCoordinator`), never here.
public struct WidgetSnapshotBuilder: Sendable {
    /// Default number of rows persisted per filter. Enough for the largest
    /// widget family (systemExtraLarge / macOS) with margin; the widget slices
    /// this down per family.
    public static let defaultRowCap = 16

    private let smartFilterStore: SmartFilterStore
    private let snapshotStore: WidgetSnapshotStore
    private let rowCap: Int

    public init(
        smartFilterStore: SmartFilterStore,
        snapshotStore: WidgetSnapshotStore,
        rowCap: Int = WidgetSnapshotBuilder.defaultRowCap
    ) {
        self.smartFilterStore = smartFilterStore
        self.snapshotStore = snapshotStore
        self.rowCap = rowCap
    }

    /// Regenerate widget snapshots.
    ///
    /// - Parameter filterIDs: the filters to refresh, or `nil` to refresh every
    ///   saved filter (the default the app uses, so any widget's cache stays
    ///   warm without tracking which filter is placed on which widget).
    ///
    /// Never throws: a per-filter failure is skipped so the others still refresh,
    /// and a total failure (e.g. store unavailable) is swallowed — a stale or
    /// missing snapshot degrades gracefully in the widget, it isn't fatal.
    public func regenerate(filterIDs: [UUID]? = nil) async {
        guard let filters = try? await smartFilterStore.list() else { return }

        // The index lists *all* filters (for the picker + name resolution),
        // regardless of which subset we regenerate this pass.
        let index = WidgetSnapshotIndex(
            filters: filters.map { .init(id: $0.id, name: $0.name, tintHex: $0.tintColor) },
            generatedAt: Date()
        )
        try? snapshotStore.writeIndex(index)

        let wanted: [SmartFilterStore.SmartFilterRecord]
        if let filterIDs {
            let set = Set(filterIDs)
            wanted = filters.filter { set.contains($0.id) }
        } else {
            wanted = filters
        }

        for filter in wanted {
            guard let matches = try? await smartFilterStore.evaluate(id: filter.id) else { continue }
            let openCount = matches.reduce(into: 0) { count, task in
                if task.status.isClosed == false { count += 1 }
            }
            let rows = matches.prefix(rowCap).map {
                WidgetSnapshot.Row(id: $0.id, title: $0.title, status: $0.status)
            }
            let snapshot = WidgetSnapshot(
                filterID: filter.id,
                filterName: filter.name,
                tintHex: filter.tintColor,
                generatedAt: Date(),
                totalCount: matches.count,
                openCount: openCount,
                tasks: Array(rows)
            )
            try? snapshotStore.write(snapshot)
        }

        // Drop caches for filters that no longer exist.
        snapshotStore.pruneFilters(keeping: Set(filters.map(\.id)))
    }
}
