import Testing
import Foundation
@testable import LillistCore

/// Failure-path regression tests for ``WidgetSnapshotBuilder`` — `LIL-93`.
///
/// These are the tests `04136f2f` could not write. That fix corrected
/// `performRegenerate`'s fail-*unsafe* branches (a thrown read was converted to
/// `[]` via `?? []` and then written to disk as an authoritative empty
/// snapshot), but the builder took a *concrete* `SmartFilterStore`, so no test
/// could inject a throwing read and the branches were unreachable. Shipping a
/// fix without its regression test was logged as an explicit exception to the
/// project's rule; ``WidgetSnapshotSource`` closes it.
///
/// The defect class in one sentence: **"your read failed" and "you have no
/// tasks" must never produce the same file.** A stale snapshot is wrong by age
/// and self-corrects on the next successful pass; a zeroed snapshot is wrong by
/// content, indistinguishable from truth, and sticks. Every test here pins one
/// side of that distinction — `genuinelyEmptyResultIsWritten` pins the other,
/// and is the reason the rest cannot be satisfied by simply never writing.
@Suite("WidgetSnapshotBuilder — failure paths")
struct WidgetSnapshotBuilderFailureTests {

    // MARK: - Fixtures

    /// Which read should throw. The builder makes three distinct kinds of read,
    /// and each has its own required failure posture.
    private enum FailurePoint: Sendable {
        case none
        /// `listFilters()` — the filter roster.
        case list
        /// `evaluateFilter(id:)` for a specific saved filter.
        case savedFilter(UUID)
        /// The shared closed-today grace set.
        case graceSet
        /// The "No Filter" sentinel's open-task read.
        case sentinel
        /// `LIL-95`: the parent-resolution `lookupTasks(ids:)` read.
        case lookup
    }

    private struct SourceError: Error {}

    /// A ``WidgetSnapshotSource``/``WidgetTaskLookup`` double that answers from
    /// fixed data and throws at one chosen point. Counts reads so a test can
    /// assert a path was *not* taken.
    private actor FakeSource: WidgetSnapshotSource, WidgetTaskLookup {
        private let filters: [SmartFilterStore.SmartFilterRecord]
        private let tasksByFilter: [UUID: [TaskStore.TaskRecord]]
        private let closedToday: [TaskStore.TaskRecord]
        private let openTasks: [TaskStore.TaskRecord]
        private let lookupTable: [UUID: TaskStore.TaskRecord]
        private let failAt: FailurePoint

        private(set) var listCalls = 0
        private(set) var filterCalls = 0
        private(set) var groupCalls = 0
        private(set) var lookupCalls = 0

        init(
            filters: [SmartFilterStore.SmartFilterRecord] = [],
            tasksByFilter: [UUID: [TaskStore.TaskRecord]] = [:],
            closedToday: [TaskStore.TaskRecord] = [],
            openTasks: [TaskStore.TaskRecord] = [],
            lookupTable: [UUID: TaskStore.TaskRecord] = [:],
            failAt: FailurePoint = .none
        ) {
            self.filters = filters
            self.tasksByFilter = tasksByFilter
            self.closedToday = closedToday
            self.openTasks = openTasks
            self.lookupTable = lookupTable
            self.failAt = failAt
        }

        func listFilters() async throws -> [SmartFilterStore.SmartFilterRecord] {
            listCalls += 1
            if case .list = failAt { throw SourceError() }
            return filters
        }

        func evaluateFilter(id: UUID) async throws -> [TaskStore.TaskRecord] {
            filterCalls += 1
            if case .savedFilter(let failing) = failAt, failing == id { throw SourceError() }
            return tasksByFilter[id] ?? []
        }

        /// The builder distinguishes its two group reads by predicate, so the
        /// fake does too: the grace set is the `closedToday` group, anything
        /// else is the sentinel's open-task read.
        func evaluateGroup(
            _ group: PredicateGroup,
            sort: SortField,
            ascending: Bool
        ) async throws -> [TaskStore.TaskRecord] {
            groupCalls += 1
            let isGraceSet = group == WidgetSnapshotBuilder.closedTodayGroup
            switch failAt {
            case .graceSet where isGraceSet: throw SourceError()
            case .sentinel where !isGraceSet: throw SourceError()
            default: return isGraceSet ? closedToday : openTasks
            }
        }

        func lookupTasks(ids: [UUID]) async throws -> [TaskStore.TaskRecord] {
            lookupCalls += 1
            if case .lookup = failAt { throw SourceError() }
            return ids.compactMap { lookupTable[$0] }
        }
    }

    private func filter(_ name: String, id: UUID = UUID()) -> SmartFilterStore.SmartFilterRecord {
        .init(
            id: id,
            name: name,
            group: .init(combinator: .all, predicates: []),
            sortField: .manualPosition,
            sortAscending: true,
            isPinned: false,
            position: 0
        )
    }

    private func task(
        _ title: String,
        status: Status = .todo,
        position: Double = 0,
        parentID: UUID? = nil
    ) -> TaskStore.TaskRecord {
        .init(
            id: UUID(),
            title: title,
            notes: "",
            status: status,
            start: nil,
            startHasTime: false,
            deadline: nil,
            deadlineHasTime: false,
            position: position,
            isPinned: false,
            parentID: parentID,
            createdAt: Date(),
            modifiedAt: Date(),
            closedAt: status.isClosed ? Date() : nil,
            deletedAt: nil
        )
    }

    private func tempSnapshotStore() -> (store: WidgetSnapshotStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotBuilderFailureTests-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(rootDirectory: dir), dir)
    }

    /// A known-good snapshot on disk, so a test can prove a later failed pass
    /// left it *intact* rather than overwriting it with zeros.
    private func seedSnapshot(_ store: WidgetSnapshotStore, filterID: UUID, title: String) throws {
        try store.write(
            WidgetSnapshot(
                filterID: filterID,
                filterName: "Seeded",
                tintHex: nil,
                generatedAt: Date(timeIntervalSince1970: 1_000_000),
                totalCount: 1,
                openCount: 1,
                tasks: [.init(id: UUID(), title: title, status: .todo)]
            )
        )
    }

    // MARK: - 1. A throwing saved-filter read must not clobber that filter

    @Test("A saved filter whose read throws keeps its previous snapshot, and its siblings still refresh")
    func throwingSavedFilterReadLeavesPriorSnapshotIntact() async throws {
        let doomed = filter("Doomed")
        let healthy = filter("Healthy")
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedSnapshot(snapStore, filterID: doomed.id, title: "PRIOR")

        let source = FakeSource(
            filters: [doomed, healthy],
            tasksByFilter: [healthy.id: [task("Fresh")]],
            failAt: .savedFilter(doomed.id)
        )
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore).regenerate()

        let kept = try #require(snapStore.read(filterID: doomed.id))
        #expect(kept.tasks.map(\.title) == ["PRIOR"], "a failed read must not overwrite the prior snapshot")
        #expect(kept.filterName == "Seeded")

        let refreshed = try #require(snapStore.read(filterID: healthy.id))
        #expect(refreshed.tasks.map(\.title) == ["Fresh"], "one filter's failure must not abort its siblings")
    }

    // MARK: - 2. A throwing sentinel read must write nothing at all

    @Test("A throwing sentinel read writes NO sentinel snapshot rather than an empty one")
    func throwingSentinelReadWritesNothing() async throws {
        let saved = filter("Saved")
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = FakeSource(
            filters: [saved],
            tasksByFilter: [saved.id: [task("Real")]],
            failAt: .sentinel
        )
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore).regenerate()

        #expect(
            snapStore.read(filterID: WidgetSnapshot.unfilteredID) == nil,
            "the C4 defect: a thrown sentinel read was persisted as an authoritative empty snapshot"
        )
        #expect(snapStore.read(filterID: saved.id) != nil, "saved filters written before the sentinel still stand")
    }

    @Test("A throwing sentinel read leaves an existing sentinel snapshot intact")
    func throwingSentinelReadLeavesPriorSentinelIntact() async throws {
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedSnapshot(snapStore, filterID: WidgetSnapshot.unfilteredID, title: "PRIOR")

        let source = FakeSource(failAt: .sentinel)
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore).regenerate()

        let kept = try #require(snapStore.read(filterID: WidgetSnapshot.unfilteredID))
        #expect(kept.tasks.map(\.title) == ["PRIOR"])
    }

    // MARK: - 3. A throwing grace-set read must abort the whole pass

    @Test("A throwing grace-set read aborts the pass before any snapshot is written")
    func throwingGraceSetReadAbortsPass() async throws {
        let saved = filter("Saved")
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = FakeSource(
            filters: [saved],
            tasksByFilter: [saved.id: [task("Never written")]],
            failAt: .graceSet
        )
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore).regenerate()

        // The grace set feeds `ordered` in EVERY writeSnapshot call, so degrading
        // it to empty would under-report totalCount on every snapshot this pass —
        // wrong data, silently, everywhere. Aborting is the only safe posture.
        #expect(snapStore.read(filterID: saved.id) == nil)
        #expect(snapStore.read(filterID: WidgetSnapshot.unfilteredID) == nil)
        #expect(await source.filterCalls == 0, "the pass must abort before evaluating any filter")
    }

    @Test("A throwing filter-roster read aborts before any read of task data")
    func throwingListAbortsPass() async throws {
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = FakeSource(failAt: .list)
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore).regenerate()

        #expect(snapStore.read(filterID: WidgetSnapshot.unfilteredID) == nil)
        #expect(await source.groupCalls == 0)
        #expect(await source.filterCalls == 0)
    }

    // MARK: - 4. A genuinely empty result MUST still be written

    @Test("A successful read of genuinely zero tasks DOES write an empty snapshot")
    func genuinelyEmptyResultIsWritten() async throws {
        let saved = filter("Empty")
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Everything succeeds; there is simply nothing to show.
        let source = FakeSource(filters: [saved], tasksByFilter: [saved.id: []])
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore).regenerate()

        // This is the counterweight to every test above. "Never write on empty"
        // would satisfy them all and be wrong: an emptied filter must be able to
        // report itself empty, or the widget shows stale rows forever.
        let sentinel = try #require(
            snapStore.read(filterID: WidgetSnapshot.unfilteredID),
            "a successful empty read is an ANSWER and must be persisted"
        )
        #expect(sentinel.totalCount == 0)
        #expect(sentinel.tasks.isEmpty)

        let savedSnap = try #require(snapStore.read(filterID: saved.id))
        #expect(savedSnap.totalCount == 0)
        #expect(savedSnap.tasks.isEmpty)
    }

    @Test("A successful empty read overwrites a previously non-empty snapshot")
    func genuinelyEmptyResultOverwritesStaleContent() async throws {
        let saved = filter("Emptied")
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedSnapshot(snapStore, filterID: saved.id, title: "STALE")

        let source = FakeSource(filters: [saved], tasksByFilter: [saved.id: []])
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore).regenerate()

        let snap = try #require(snapStore.read(filterID: saved.id))
        #expect(snap.tasks.isEmpty, "clearing a filter must clear its snapshot — the failure paths must not over-generalize")
        #expect(snap.filterName == "Emptied")
    }

    // MARK: - regenerateAuthoritatively: a failed pass must not prune

    @Test("A failed pass never writes the index or prunes, even authoritatively")
    func failedPassDoesNotPruneAuthoritatively() async throws {
        let survivor = filter("Survivor")
        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedSnapshot(snapStore, filterID: survivor.id, title: "PRIOR")

        // The roster read fails, so `performRegenerate` returns nil. Pruning on
        // that would delete live snapshots on the strength of a failed read.
        let source = FakeSource(failAt: .list)
        await WidgetSnapshotBuilder(smartFilterStore: source, taskLookup: source, snapshotStore: snapStore)
            .regenerateAuthoritatively()

        #expect(snapStore.read(filterID: survivor.id) != nil, "a failed read must never be grounds for deletion")
        #expect(snapStore.readIndex() == nil, "no index may be written from a failed pass")
    }
}
