import Testing
import Foundation
@testable import LillistCore

/// Regression tests for LIL-91: the widget's configuration-intent resolution
/// hung on an unbounded Core Data open, so WidgetKit never resolved
/// `SelectFilterIntent` and therefore never called `timeline(for:in:)` — the
/// widget rendered only its container background.
///
/// The three defects pinned here (see `.rca/ios-widget-shows-redacted-content/DIAGNOSIS.md`):
/// - **C1** the sentinel-only case did a store read to answer a question whose
///   answer is a compile-time constant — and that is the default configuration
///   of every freshly added widget;
/// - **C2** nothing bounded the wait, in a process with a hard wall-clock budget;
/// - **C3** the expensive live read led and the cheap index read was only a
///   throw-fallback, so slowness (as opposed to failure) was never survivable.
@Suite("WidgetFilterCatalog — bounded, cheap-first filter resolution")
struct WidgetFilterCatalogTests {

    private func entry(_ name: String, id: UUID = UUID()) -> WidgetSnapshotIndex.Entry {
        .init(id: id, name: name, tintHex: nil)
    }

    /// Counts reads so a test can assert a path was never taken — the only way
    /// to pin C1, whose whole content is "no read happens".
    private actor ReadLog {
        private(set) var indexReads = 0
        private(set) var liveReads = 0
        func recordIndex() { indexReads += 1 }
        func recordLive() { liveReads += 1 }
    }

    // MARK: - C1: the sentinel short-circuit

    @Test("Resolving only the unfiltered sentinel performs NO store read")
    func sentinelOnlyResolvesWithoutReading() async {
        let log = ReadLog()
        let catalog = WidgetFilterCatalog(
            indexRead: { await log.recordIndex(); return [] },
            liveRead: { await log.recordLive(); return [] }
        )

        let resolved = await catalog.resolve(ids: [WidgetSnapshot.unfilteredID])

        #expect(resolved.includesUnfiltered)
        #expect(resolved.saved.isEmpty)
        #expect(await log.indexReads == 0, "C1: the sentinel's answer is a constant — no index read")
        #expect(await log.liveReads == 0, "C1: the sentinel's answer is a constant — no store open")
    }

    @Test("An empty identifier set performs NO store read")
    func emptyIdentifiersResolveWithoutReading() async {
        let log = ReadLog()
        let catalog = WidgetFilterCatalog(
            indexRead: { await log.recordIndex(); return [] },
            liveRead: { await log.recordLive(); return [] }
        )

        let resolved = await catalog.resolve(ids: [])

        #expect(resolved.includesUnfiltered == false)
        #expect(resolved.saved.isEmpty)
        #expect(await log.liveReads == 0)
    }

    @Test("Resolving a saved filter id DOES read, and returns only what was asked for")
    func savedFilterResolutionReads() async {
        let wanted = entry("Today")
        let other = entry("Stale")
        let catalog = WidgetFilterCatalog(
            indexRead: { [wanted, other] },
            liveRead: { nil }
        )

        let resolved = await catalog.resolve(ids: [wanted.id])

        #expect(resolved.includesUnfiltered == false)
        #expect(resolved.saved == [wanted])
    }

    @Test("Sentinel mixed with a saved id resolves both")
    func sentinelPlusSavedResolvesBoth() async {
        let wanted = entry("Today")
        let catalog = WidgetFilterCatalog(indexRead: { [wanted] }, liveRead: { nil })

        let resolved = await catalog.resolve(ids: [WidgetSnapshot.unfilteredID, wanted.id])

        #expect(resolved.includesUnfiltered)
        #expect(resolved.saved == [wanted])
    }

    // MARK: - C2: the wait is bounded

    @Test("A hanging live read cannot block resolution past the budget")
    func hangingLiveReadIsBounded() async {
        let index = [entry("Today")]
        let catalog = WidgetFilterCatalog(
            budget: .milliseconds(120),
            indexRead: { nil },                     // force the live path
            liveRead: {
                try? await Task.sleep(for: .seconds(30))   // the hang under investigation
                return index
            }
        )

        let started = ContinuousClock.now
        let filters = await catalog.filters()
        let elapsed = ContinuousClock.now - started

        #expect(filters.isEmpty, "a hang yields the empty fallback, never a stall")
        #expect(elapsed < .seconds(5), "C2: bounded — took \(elapsed)")
    }

    @Test("A hanging live read still cannot block when the index is available")
    func hangingLiveReadNeverConsultedWhenIndexPresent() async {
        let index = [entry("Today"), entry("Stale")]
        let catalog = WidgetFilterCatalog(
            budget: .milliseconds(120),
            indexRead: { index },
            liveRead: {
                try? await Task.sleep(for: .seconds(30))
                return []
            }
        )

        let started = ContinuousClock.now
        let filters = await catalog.filters()
        let elapsed = ContinuousClock.now - started

        #expect(filters == index)
        #expect(elapsed < .seconds(5), "C3: the cheap path answers without awaiting the slow one")
    }

    // MARK: - C3: cheapest source leads

    @Test("The index is preferred and the live store is never opened when it answers")
    func indexLeadsAndLiveIsNotOpened() async {
        let log = ReadLog()
        let index = [entry("Today")]
        let catalog = WidgetFilterCatalog(
            indexRead: { await log.recordIndex(); return index },
            liveRead: { await log.recordLive(); return [] }
        )

        let filters = await catalog.filters()

        #expect(filters == index)
        #expect(await log.indexReads == 1)
        #expect(await log.liveReads == 0, "C3: live store is an enhancement, not a prerequisite")
    }

    @Test("A missing index falls back to the live store")
    func missingIndexFallsBackToLive() async {
        let live = [entry("Today")]
        let catalog = WidgetFilterCatalog(indexRead: { nil }, liveRead: { live })

        #expect(await catalog.filters() == live)
    }

    @Test("An empty-but-present index is authoritative — a user with no saved filters is not a failure")
    func emptyIndexIsAuthoritative() async {
        let log = ReadLog()
        let catalog = WidgetFilterCatalog(
            indexRead: { [] },
            liveRead: { await log.recordLive(); return [self.entry("Today")] }
        )

        #expect(await catalog.filters().isEmpty)
        #expect(await log.liveReads == 0, "an empty index is an answer, not a miss")
    }

    @Test("Both sources unavailable degrades to empty rather than hanging or trapping")
    func bothSourcesUnavailableDegradesEmpty() async {
        let catalog = WidgetFilterCatalog(indexRead: { nil }, liveRead: { nil })
        #expect(await catalog.filters().isEmpty)
    }
}

/// `withBudget` is the bound C2 introduces. It is deliberately *abandonment*,
/// not cancellation: a Core Data stack open is not cancellable, so the slow work
/// is left to finish (and populate its own cache) while the caller proceeds.
@Suite("withBudget — bounded wait for uncancellable work")
struct WithBudgetTests {

    @Test("Returns the value when the operation finishes inside the budget")
    func fastOperationReturnsValue() async {
        let value = await withBudget(.seconds(5)) { 42 }
        #expect(value == 42)
    }

    @Test("Returns nil when the operation exceeds the budget")
    func slowOperationTimesOut() async {
        let value = await withBudget(.milliseconds(100)) {
            try? await Task.sleep(for: .seconds(30))
            return 42
        }
        #expect(value == nil)
    }

    @Test("Returns promptly on timeout rather than awaiting the abandoned work")
    func timeoutDoesNotAwaitAbandonedWork() async {
        let started = ContinuousClock.now
        _ = await withBudget(.milliseconds(100)) {
            try? await Task.sleep(for: .seconds(30))
            return 42
        }
        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .seconds(5), "took \(elapsed)")
    }

    @Test("A nil-returning operation is distinguishable from a timeout")
    func nilResultIsNotATimeout() async {
        let value: Int?? = await withBudget(.seconds(5)) { Int?.none }
        // Outer nil == timeout; inner nil == the operation's own nil.
        #expect(value != nil, "the operation completed, so the outer optional is non-nil")
        #expect(value ?? 1 == nil)
    }
}
