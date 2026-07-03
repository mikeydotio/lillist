import Foundation

/// Produces ``WidgetSnapshot`` JSON for the widget extension from the live
/// stores. Runs in the app (or a writing extension) whenever task/filter data
/// changes; the widget only ever *reads* the result.
///
/// **Pure LillistCore — no WidgetKit.** The `WidgetCenter.reloadTimelines(...)`
/// call that follows a regeneration lives in the app/extension target (e.g.
/// `WidgetRefreshCoordinator`), never here.
///
/// Every snapshot orders **open tasks first, just-completed tasks at the
/// bottom**: a task closed *today* is retained at the end of the list (so
/// checking it off in the widget makes it sink rather than vanish) and drops off
/// once the day rolls over. The "No Filter" sentinel snapshot
/// (``WidgetSnapshot/unfilteredID``) is rebuilt alongside the saved filters so a
/// freshly added, unconfigured widget has content.
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
    ///   warm without tracking which filter is placed on which widget). The
    ///   "No Filter" sentinel is (re)built whenever `filterIDs` is `nil` or
    ///   explicitly contains ``WidgetSnapshot/unfilteredID`` — it reflects *all*
    ///   tasks, so any task change can affect it.
    ///
    /// Never throws: a per-filter failure is skipped so the others still refresh,
    /// and a total failure (e.g. store unavailable) is swallowed — a stale or
    /// missing snapshot degrades gracefully in the widget, it isn't fatal.
    public func regenerate(filterIDs: [UUID]? = nil) async {
        guard let filters = try? await smartFilterStore.list() else { return }

        // The index lists *all* saved filters (for the picker + name resolution),
        // regardless of which subset we regenerate this pass. The sentinel is
        // injected by the config picker directly, so it is not listed here.
        let index = WidgetSnapshotIndex(
            filters: filters.map { .init(id: $0.id, name: $0.name, tintHex: $0.tintColor) },
            generatedAt: Date()
        )
        try? snapshotStore.writeIndex(index)

        // The grace set: tasks closed *today*, most-recent first. Computed once
        // and shared across every target, since a just-completed task should
        // sink to the bottom of whichever widget surfaced it.
        let closedToday = (try? await smartFilterStore.evaluate(
            group: Self.closedTodayGroup,
            sort: .closedAt,
            ascending: false
        )) ?? []

        // Saved filters to refresh this pass.
        let wantedSaved: [SmartFilterStore.SmartFilterRecord]
        if let filterIDs {
            let set = Set(filterIDs)
            wantedSaved = filters.filter { set.contains($0.id) }
        } else {
            wantedSaved = filters
        }

        for filter in wantedSaved {
            guard let matches = try? await smartFilterStore.evaluate(id: filter.id) else { continue }
            writeSnapshot(
                filterID: filter.id,
                filterName: filter.name,
                tintHex: filter.tintColor,
                matches: matches,
                closedToday: closedToday
            )
        }

        // The "No Filter" (all tasks) sentinel: open tasks (its base query
        // excludes closed so historical done tasks don't pile up), plus today's
        // grace set at the bottom.
        if filterIDs == nil || filterIDs?.contains(WidgetSnapshot.unfilteredID) == true {
            let openMatches = (try? await smartFilterStore.evaluate(
                group: Self.unfilteredOpenGroup,
                sort: .modifiedAt,
                ascending: false
            )) ?? []
            writeSnapshot(
                filterID: WidgetSnapshot.unfilteredID,
                filterName: "",
                tintHex: nil,
                matches: openMatches,
                closedToday: closedToday
            )
        }

        // Drop caches for filters that no longer exist — but always keep the
        // sentinel snapshot.
        snapshotStore.pruneFilters(keeping: Set(filters.map(\.id)).union([WidgetSnapshot.unfilteredID]))
    }

    /// Order a target's tasks (open first, closed-today grace set last) and
    /// persist the snapshot. `matches` is already in the target's sort order;
    /// `closedToday` is the shared grace set.
    ///
    /// - Open tasks keep the target's sort.
    /// - Closed tasks the target *legitimately* matched (e.g. a "Recently
    ///   Closed" filter) are kept in the target's sort, sunk below the open rows.
    /// - Tasks closed today that the target filtered out (the just-completed
    ///   ones) are appended at the very bottom.
    private func writeSnapshot(
        filterID: UUID,
        filterName: String,
        tintHex: String?,
        matches: [TaskStore.TaskRecord],
        closedToday: [TaskStore.TaskRecord]
    ) {
        let matchIDs = Set(matches.map(\.id))
        let open = matches.filter { $0.status.isClosed == false }
        let closedInMatches = matches.filter { $0.status.isClosed }
        let grace = closedToday.filter { matchIDs.contains($0.id) == false }
        let ordered = open + closedInMatches + grace

        let rows = ordered.prefix(rowCap).map {
            WidgetSnapshot.Row(id: $0.id, title: $0.title, status: $0.status)
        }
        let snapshot = WidgetSnapshot(
            filterID: filterID,
            filterName: filterName,
            tintHex: tintHex,
            generatedAt: Date(),
            totalCount: ordered.count,
            openCount: open.count,
            tasks: Array(rows)
        )
        try? snapshotStore.write(snapshot)
    }

    // MARK: - Ad-hoc predicate groups

    /// Open (not-closed) tasks — the base set for the "No Filter" view. The
    /// compiler implicitly excludes trash + archived, so this is "everything I
    /// still have to do".
    static let unfilteredOpenGroup = PredicateGroup(
        combinator: .all,
        predicates: [
            .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
        ]
    )

    /// Tasks closed today — the shared grace set appended to every target.
    static let closedTodayGroup = PredicateGroup(
        combinator: .all,
        predicates: [
            .leaf(Leaf(field: .status, op: .is, value: .statusSet([.closed]))),
            .leaf(Leaf(field: .closedAt, op: .on, value: .relativeDate(.today)))
        ]
    )
}
