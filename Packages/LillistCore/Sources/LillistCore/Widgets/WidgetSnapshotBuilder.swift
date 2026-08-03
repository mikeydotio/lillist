import Foundation

/// Produces ``WidgetSnapshot`` JSON for the widget extension from the live
/// stores. Runs in the app (or a writing extension) whenever task/filter data
/// changes; the widget only ever *reads* the result.
///
/// **Pure LillistCore — no WidgetKit.** The `WidgetCenter.reloadTimelines(...)`
/// call that follows a regeneration lives behind the `WidgetTimelineReloading`
/// seam (see ``WidgetRefreshController``), never here.
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

    private let smartFilterStore: any WidgetSnapshotSource
    private let taskLookup: any WidgetTaskLookup
    private let snapshotStore: WidgetSnapshotStore
    private let rowCap: Int

    /// - Parameter smartFilterStore: the read seam. `SmartFilterStore` conforms,
    ///   so production call sites pass one directly; tests inject a failing
    ///   double to reach the error branches (`LIL-93`).
    /// - Parameter taskLookup: `LIL-95`'s parent-resolution seam. `TaskStore`
    ///   conforms, so production call sites pass their existing `TaskStore`.
    ///   Required, not defaulted: a caller that forgot to wire this would
    ///   otherwise silently ship a widget that can never render context rows,
    ///   which is exactly the kind of footgun a compiler-enforced parameter
    ///   prevents. Unused by this commit — `LIL-95`'s tree-shaping consumer
    ///   lands next.
    public init(
        smartFilterStore: any WidgetSnapshotSource,
        taskLookup: any WidgetTaskLookup,
        snapshotStore: WidgetSnapshotStore,
        rowCap: Int = WidgetSnapshotBuilder.defaultRowCap
    ) {
        self.smartFilterStore = smartFilterStore
        self.taskLookup = taskLookup
        self.snapshotStore = snapshotStore
        self.rowCap = rowCap
    }

    /// Forwards to `WidgetSnapshotStore.clearAll()` — data-sync-hardening
    /// `X11`. Call before `regenerate()` after a destructive store
    /// reset/rebuild so a stale, now-erased task can never render with a
    /// dangling deep link in the gap before the next regenerate.
    public func clearCache() {
        snapshotStore.clearAll()
    }

    /// Additive-only rebuild: (re)writes the snapshot for each requested filter
    /// id (or every saved filter when `filterIDs` is `nil`), plus the "No
    /// Filter" sentinel when in scope.
    ///
    /// - Parameter filterIDs: the filters to refresh, or `nil` to refresh every
    ///   saved filter this reader currently sees (the default the app uses, so
    ///   any widget's cache stays warm without tracking which filter is placed
    ///   on which widget). The "No Filter" sentinel is (re)built whenever
    ///   `filterIDs` is `nil` or explicitly contains ``WidgetSnapshot/unfilteredID``
    ///   — it reflects *all* tasks, so any task change can affect it.
    ///
    /// **Never deletes anything on disk, and never touches the picker
    /// index** — not even when `filterIDs` is `nil` and this read happens to
    /// come back with fewer filters than exist. data-sync-hardening `X5`: a
    /// same-device cross-process read (widget extension, Share extension,
    /// Shortcuts action) can legitimately lag a very recent write another
    /// process just made — `NSPersistentCloudKitContainer`'s cross-process
    /// propagation is asynchronous, and Core Data surfaces no error for "not
    /// caught up yet," so an incomplete read is indistinguishable from a
    /// genuinely smaller filter set at this call site. Treating either as
    /// grounds for deletion is exactly the bug; this method structurally
    /// cannot delete anything, so it's safe to call from *any* process,
    /// including the widget's own cold-cache-miss rebuild
    /// (``FilterTimelineProvider``), which is definitionally this shape — one
    /// filter, additive, no authority implied. See
    /// ``regenerateAuthoritatively()`` for the one call site allowed to prune.
    ///
    /// Never throws: a per-filter failure is skipped so the others still refresh,
    /// and a total failure (e.g. store unavailable) is swallowed — a stale or
    /// missing snapshot degrades gracefully in the widget, it isn't fatal.
    public func regenerate(filterIDs: [UUID]? = nil) async {
        _ = await performRegenerate(filterIDs: filterIDs)
    }

    /// Full regeneration that also reconciles the on-disk cache to match the
    /// read: writes the picker index and prunes snapshots for filters no
    /// longer present.
    ///
    /// **Only safe to call from the main app process** (via
    /// `WidgetRefreshController`, which is the only caller). Pruning requires
    /// trusting an empty/incomplete read as ground truth for "this filter is
    /// gone" — a trust `regenerate(filterIDs:)`'s doc comment explains no
    /// cross-process reader can extend. The app process is the one place that
    /// trust is actually earned: Core Data serializes `context.perform` on one
    /// queue, so a fetch issued after this process's own save always observes
    /// it — the only kind of staleness that could cause over-pruning
    /// (deleting a snapshot for a filter that still exists) cannot occur
    /// here. Under-pruning relative to another device's very recent CloudKit
    /// write is still possible and is safe by design (the stale snapshot just
    /// persists a little longer, never deleted incorrectly).
    ///
    /// Never throws, same swallow-and-degrade contract as `regenerate(filterIDs:)`.
    public func regenerateAuthoritatively() async {
        guard let filters = await performRegenerate(filterIDs: nil) else { return }

        // The index lists *all* saved filters (for the picker + name
        // resolution). The sentinel is injected by the config picker
        // directly, so it is not listed here.
        let index = WidgetSnapshotIndex(
            filters: filters.map { .init(id: $0.id, name: $0.name, tintHex: $0.tintColor) },
            generatedAt: Date()
        )
        try? snapshotStore.writeIndex(index)

        // Drop caches for filters that no longer exist — but always keep the
        // sentinel snapshot. Safe here (and only here): see this method's own
        // doc comment for why this read can be trusted as ground truth.
        snapshotStore.pruneFilters(keeping: Set(filters.map(\.id)).union([WidgetSnapshot.unfilteredID]))
    }

    /// Shared body: write per-filter snapshots for `filterIDs` (or every
    /// filter this read sees, when `nil`) plus the sentinel when in scope.
    /// Returns the full filter list this read produced (for
    /// ``regenerateAuthoritatively()``'s index/prune step) — `nil` only when
    /// the underlying read itself failed (store unavailable, fetch error),
    /// which already means neither caller should write anything further.
    private func performRegenerate(filterIDs: [UUID]?) async -> [SmartFilterStore.SmartFilterRecord]? {
        guard let filters = try? await smartFilterStore.listFilters() else { return nil }

        // The grace set: tasks closed *today*, most-recent first. Computed once
        // and shared across every target, since a just-completed task should
        // sink to the bottom of whichever widget surfaced it.
        //
        // A failure here aborts the whole pass rather than degrading to an empty
        // grace set: this list feeds `ordered` in every `writeSnapshot` call, so
        // swallowing the error would under-report `totalCount` on *each* snapshot
        // written this pass — wrong data, silently, everywhere.
        guard let closedToday = try? await smartFilterStore.evaluateGroup(
            Self.closedTodayGroup,
            sort: .closedAt,
            ascending: false
        ) else { return nil }

        // Saved filters to refresh this pass.
        let wantedSaved: [SmartFilterStore.SmartFilterRecord]
        if let filterIDs {
            let set = Set(filterIDs)
            wantedSaved = filters.filter { set.contains($0.id) }
        } else {
            wantedSaved = filters
        }

        for filter in wantedSaved {
            guard let matches = try? await smartFilterStore.evaluateFilter(id: filter.id) else { continue }
            writeSnapshot(
                filterID: filter.id,
                filterName: filter.name,
                tintHex: filter.tintColor,
                sortField: filter.sortField,
                matches: matches,
                closedToday: closedToday
            )
        }

        // The "No Filter" (all tasks) sentinel: open tasks (its base query
        // excludes closed so historical done tasks don't pile up), plus today's
        // grace set at the bottom.
        //
        // `guard let … else { return filters }`, NOT `(try?) ?? []`: a thrown
        // read and a genuinely empty task list are different facts, and only one
        // of them may be written. The previous `?? []` conflated them and
        // persisted a *failure* as an authoritative empty snapshot — the widget
        // then rendered a card with no rows and no way to tell it was wrong.
        // Failing to write leaves the prior snapshot intact, which is stale at
        // worst; writing zeros is wrong. This matches the saved-filter loop
        // above, which already fails safe via `continue`.
        if filterIDs == nil || filterIDs?.contains(WidgetSnapshot.unfilteredID) == true {
            guard let openMatches = try? await smartFilterStore.evaluateGroup(
                Self.unfilteredOpenGroup,
                sort: .manualPosition,
                ascending: true
            ) else { return filters }
            writeSnapshot(
                filterID: WidgetSnapshot.unfilteredID,
                filterName: "",
                tintHex: nil,
                sortField: .manualPosition,
                matches: openMatches,
                closedToday: closedToday
            )
        }

        return filters
    }

    /// Order a target's tasks (open first, closed-today grace set last) and
    /// persist the snapshot. `matches` is already in the target's sort order;
    /// `closedToday` is the shared grace set.
    ///
    /// - Open tasks keep the target's sort *when it is stable under a status
    ///   transition*; a volatile sort (`.modifiedAt`/`.status`, or the No-Filter
    ///   sentinel) is replaced with the canonical `SiblingOrder` (position, then
    ///   id) so advancing a task in the widget doesn't make its row jump. Only
    ///   completing a task (which moves it out of the open slice) reorders it.
    /// - Closed tasks the target *legitimately* matched (e.g. a "Recently
    ///   Closed" filter) are kept in the target's sort, sunk below the open rows.
    /// - Tasks closed today that the target filtered out (the just-completed
    ///   ones) are appended at the very bottom.
    private func writeSnapshot(
        filterID: UUID,
        filterName: String,
        tintHex: String?,
        sortField: SortField,
        matches: [TaskStore.TaskRecord],
        closedToday: [TaskStore.TaskRecord]
    ) {
        let matchIDs = Set(matches.map(\.id))
        let openRaw = matches.filter { $0.status.isClosed == false }
        let open = sortField.isStableUnderStatusTransition
            ? openRaw
            : openRaw.sorted {
                SiblingOrder.precedes(
                    positionA: $0.position, idA: $0.id,
                    positionB: $1.position, idB: $1.id
                )
            }
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
