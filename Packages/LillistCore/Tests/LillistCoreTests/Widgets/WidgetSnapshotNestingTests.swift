import Testing
import Foundation
@testable import LillistCore

/// `LIL-95`: subtasks nest under their parents in the widget instead of
/// rendering as flat, indistinguishable peer rows.
///
/// Part A tests ``WidgetSnapshotBuilder/shapeRows(ordered:contextByID:)``
/// directly — pure, synchronous, no Core Data — for the actual tree-shaping
/// rules. Part B exercises the full async `regenerate()` pipeline against a
/// real in-memory store, the way `WidgetSnapshotBuilderTests` does, to prove
/// the pieces are wired together correctly end-to-end.
@Suite("WidgetSnapshotBuilder — LIL-95 nesting")
struct WidgetSnapshotNestingTests {
    // MARK: - Part A: shapeRows fixtures

    private func task(
        _ title: String,
        status: Status = .todo,
        position: Double = 0,
        parentID: UUID? = nil,
        id: UUID = UUID()
    ) -> TaskStore.TaskRecord {
        .init(
            id: id,
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

    // MARK: - Part A: shapeRows

    @Test("a child nests under its matching parent, never rendering above it")
    func childNestsUnderMatchingParent() {
        let parent = task("Ship v0.21")
        let child = task("Write release notes", parentID: parent.id)
        let rows = WidgetSnapshotBuilder.shapeRows(ordered: [parent, child], contextByID: [:])

        #expect(rows.map(\.title) == ["Ship v0.21", "Write release notes"])
        #expect(rows.map(\.depth) == [0, 1])
        #expect(rows.map(\.isContext) == [false, false])
        #expect(rows[1].parentID == parent.id)
    }

    @Test("two children of different parents stay in their own groups")
    func siblingGroupsDoNotCrossContaminate() {
        let parentA = task("Project A", position: 0)
        let childA = task("A subtask", position: 1, parentID: parentA.id)
        let parentB = task("Project B", position: 2)
        let childB = task("B subtask", position: 3, parentID: parentB.id)
        let rows = WidgetSnapshotBuilder.shapeRows(
            ordered: [parentA, childA, parentB, childB],
            contextByID: [:]
        )

        #expect(rows.map(\.title) == ["Project A", "A subtask", "Project B", "B subtask"])
        #expect(rows.map(\.depth) == [0, 1, 0, 1])
    }

    @Test("an orphan child (parent not in ordered) gets a dimmed context row above it")
    func orphanChildGetsContextRow() {
        let parent = task("Ship v0.21")
        let child = task("Write release notes", parentID: parent.id)
        // Parent does NOT match the filter, so it's absent from `ordered` —
        // only resolvable via the fetched `contextByID`.
        let rows = WidgetSnapshotBuilder.shapeRows(ordered: [child], contextByID: [parent.id: parent])

        #expect(rows.map(\.title) == ["Ship v0.21", "Write release notes"])
        #expect(rows.map(\.isContext) == [true, false])
        #expect(rows.map(\.depth) == [0, 1])
        #expect(rows[1].parentID == parent.id)
    }

    @Test("grandparent (matching) + parent (missing) + child (matching) renders 3 tiers")
    func threeTierChainWithMissingMiddleParent() {
        let grandparent = task("Quarter goals", position: 0)
        let parent = task("Ship v0.21", position: 1, parentID: grandparent.id)
        let child = task("Write release notes", position: 2, parentID: parent.id)
        let rows = WidgetSnapshotBuilder.shapeRows(
            ordered: [grandparent, child],
            contextByID: [parent.id: parent]
        )

        #expect(rows.map(\.title) == ["Quarter goals", "Ship v0.21", "Write release notes"])
        #expect(rows.map(\.isContext) == [false, true, false])
        #expect(rows.map(\.depth) == [0, 1, 2])
    }

    @Test("depth clamps at tier 2 — a depth-4 descendant renders at tier 2, not tier 4")
    func depthClampsAtTierTwo() {
        let root = task("Root", position: 0)
        let child = task("Child", position: 1, parentID: root.id)
        let grandchild = task("Grandchild", position: 2, parentID: child.id)
        let greatGrandchild = task("Great-grandchild", position: 3, parentID: grandchild.id)
        let greatGreatGrandchild = task("Great-great-grandchild", position: 4, parentID: greatGrandchild.id)
        let rows = WidgetSnapshotBuilder.shapeRows(
            ordered: [root, child, grandchild, greatGrandchild, greatGreatGrandchild],
            contextByID: [:]
        )

        #expect(rows.map(\.title) == [
            "Root", "Child", "Grandchild", "Great-grandchild", "Great-great-grandchild",
        ])
        #expect(rows.map(\.depth) == [0, 1, 2, 2, 2], "tier 2 is the floor — deeper descendants stop indenting further")
    }

    @Test("a parent already present as a member heads its own group — no context row synthesized")
    func memberParentNeedsNoContextRow() {
        // Simulates a grace-band parent: it's a member of `ordered` (just
        // ranked late, e.g. the closed-today tail), so it must NOT be
        // duplicated as a context row even though it's not literally adjacent.
        let parent = task("Ship v0.21", status: .closed, position: 5)
        let child = task("Write release notes", position: 0, parentID: parent.id)
        // `ordered`'s own index order puts the open child first, the closed
        // parent last — mirroring how writeSnapshot's open+closed bands work.
        let rows = WidgetSnapshotBuilder.shapeRows(ordered: [child, parent], contextByID: [:])

        #expect(rows.map(\.isContext) == [false, false], "the parent is a real member, never a context row")
        #expect(rows.map(\.title) == ["Ship v0.21", "Write release notes"], "the group sorts by its best-ranked member")
        #expect(rows.map(\.depth) == [0, 1])
    }

    @Test("a group sorts by its earliest-ranked member — a closed parent with an open child stays grouped with it")
    func groupSortsByBestRankedMember() {
        // `ordered`'s ARRAY POSITION is the rank `shapeRows` reads — exactly
        // what `orderedBands` produces: every open task first (regardless of
        // parentage), then the closed band. So an open child is ranked ahead
        // of its own closed parent, same as it would be in a real snapshot.
        // `middle` is a standalone root ranked between the two: if the group
        // sorted by the PARENT's own late rank, `middle` would land between
        // parent and child; sorting by the child's early rank keeps the whole
        // group together, ahead of `middle`.
        let parentID = UUID()
        let child = task("Open subtask")
        let linkedChild = task("Write release notes", parentID: parentID)
        let middle = task("Standalone")
        let parent = task("Closed parent", status: .closed, id: parentID)
        // Open band first (child, linkedChild, middle), closed band last (parent).
        let rows = WidgetSnapshotBuilder.shapeRows(
            ordered: [child, linkedChild, middle, parent],
            contextByID: [:]
        )

        #expect(rows.map(\.title) == ["Open subtask", "Closed parent", "Write release notes", "Standalone"])
    }

    @Test("no nesting present reproduces the input order byte for byte")
    func noNestingPreservesOriginalOrder() {
        let a = task("A", position: 0)
        let b = task("B", position: 1)
        let c = task("C", position: 2)
        let rows = WidgetSnapshotBuilder.shapeRows(ordered: [a, b, c], contextByID: [:])

        #expect(rows.map(\.title) == ["A", "B", "C"])
        #expect(rows.map(\.depth) == [0, 0, 0])
        #expect(rows.allSatisfy { $0.isContext == false })
    }

    @Test("a parent that's neither a member nor resolvable via contextByID promotes its child to root")
    func unresolvableParentPromotesChildToRoot() {
        let missingParentID = UUID()
        let child = task("Orphaned task", parentID: missingParentID)
        // contextByID is empty: the lookup didn't find (or wasn't given) this
        // parent — e.g. it's trashed, or the lookup itself failed.
        let rows = WidgetSnapshotBuilder.shapeRows(ordered: [child], contextByID: [:])

        #expect(rows.map(\.title) == ["Orphaned task"])
        #expect(rows[0].depth == 0)
        #expect(rows[0].isContext == false)
        // The TRUE parent id is preserved even though it isn't rendered —
        // WidgetRowPlan needs it to decide the "parent not shown" marker.
        #expect(rows[0].parentID == missingParentID)
    }

    @Test("context rows never inflate the persisted row count beyond what shapeRows was given")
    func contextRowCountIsExactlyOnePerResolvedMissingParent() {
        let parentA = task("A parent")
        let childA = task("A child", parentID: parentA.id)
        let parentB = task("B parent")
        let childB1 = task("B child 1", parentID: parentB.id)
        let childB2 = task("B child 2", parentID: parentB.id)
        // Only A's parent matches (member); B's parent is missing and shared
        // by two children — must synthesize exactly ONE context row for B.
        let rows = WidgetSnapshotBuilder.shapeRows(
            ordered: [parentA, childA, childB1, childB2],
            contextByID: [parentB.id: parentB]
        )

        #expect(rows.filter(\.isContext).count == 1)
        #expect(rows.filter { $0.isContext && $0.id == parentB.id }.count == 1)
    }

    // MARK: - Part B: full async pipeline

    private func todoGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    private func tempSnapshotStore() -> (store: WidgetSnapshotStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotNestingTests-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(rootDirectory: dir), dir)
    }

    /// A filter that matches only tasks whose title starts with "Sub" — used
    /// to produce a match set containing a child but not its parent, without
    /// depending on `.ancestor`/hierarchy predicates (which point the wrong
    /// direction for this: `.isDescendantOf`, not "is a non-matching parent
    /// of").
    private func subtasksOnlyGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .startsWith, value: .string("Sub")))
        ])
    }

    @Test("end-to-end: a matched subtask whose parent doesn't match gets a context row in the persisted snapshot")
    func endToEndOrphanChildProducesContextRowInSnapshot() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let parentID = try await tasks.create(title: "Ship v0.21")
        _ = try await tasks.create(title: "Subtask: write release notes", parent: parentID)
        let filterID = try await filters.create(name: "Subtasks", group: subtasksOnlyGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: filterID))
        #expect(snap.tasks.map(\.title) == ["Ship v0.21", "Subtask: write release notes"])
        #expect(snap.tasks.map(\.isContext) == [true, false])
        #expect(snap.tasks.map(\.depth) == [0, 1])
        // The context row must never count toward the filter's own totals —
        // it didn't match the filter.
        #expect(snap.totalCount == 1)
        #expect(snap.openCount == 1)
    }

    @Test("a throwing parent lookup degrades gracefully: the pass still writes, orphans flatten instead of aborting")
    func throwingLookupDegradesGracefullyInsteadOfAborting() async throws {
        struct ThrowingLookup: WidgetTaskLookup {
            struct LookupError: Error {}
            func lookupTasks(ids: [UUID]) async throws -> [TaskStore.TaskRecord] { throw LookupError() }
        }

        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let parentID = try await tasks.create(title: "Ship v0.21")
        _ = try await tasks.create(title: "Subtask: write release notes", parent: parentID)
        let filterID = try await filters.create(name: "Subtasks", group: subtasksOnlyGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(
            smartFilterStore: filters,
            taskLookup: ThrowingLookup(),
            snapshotStore: snapStore
        )
        await builder.regenerate()

        // Unlike the grace-set read, a failed context lookup can't corrupt
        // totalCount/openCount (those never depend on it) — so degrading is
        // strictly safer than the grace-set's abort-the-pass posture.
        let snap = try #require(snapStore.read(filterID: filterID), "a lookup failure must not abort the whole pass")
        #expect(snap.tasks.map(\.title) == ["Subtask: write release notes"], "no context available, so the orphan flattens to root")
        #expect(snap.tasks.allSatisfy { $0.isContext == false })
        #expect(snap.tasks.first?.depth == 0)
    }

    @Test("the parent lookup runs once per regenerate pass, even when multiple targets share the same missing parent")
    func lookupRunsOnceAcrossAllTargetsInOnePass() async throws {
        actor CallCounter {
            private(set) var count = 0
            func increment() { count += 1 }
        }
        struct CountingLookup: WidgetTaskLookup {
            let inner: any WidgetTaskLookup
            let counter: CallCounter
            func lookupTasks(ids: [UUID]) async throws -> [TaskStore.TaskRecord] {
                await counter.increment()
                return try await inner.lookupTasks(ids: ids)
            }
        }

        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let parentID = try await tasks.create(title: "Ship v0.21")
        _ = try await tasks.create(title: "Subtask: A", parent: parentID)
        _ = try await tasks.create(title: "Subtask: B", parent: parentID)
        // Two saved filters that both surface (different) subtasks of the
        // SAME missing parent, plus the sentinel (also in scope by default) —
        // three targets sharing one missing-parent id.
        _ = try await filters.create(name: "Subtasks", group: subtasksOnlyGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let builder = WidgetSnapshotBuilder(
            smartFilterStore: filters,
            taskLookup: CountingLookup(inner: tasks, counter: counter),
            snapshotStore: snapStore
        )
        await builder.regenerate()

        #expect(await counter.count == 1, "one batched lookup for the whole pass, not one per target")
    }

    @Test("no missing parents in scope means the lookup is never called")
    func lookupSkippedWhenNothingIsMissing() async throws {
        actor CallCounter {
            private(set) var count = 0
            func increment() { count += 1 }
        }
        struct CountingLookup: WidgetTaskLookup {
            let inner: any WidgetTaskLookup
            let counter: CallCounter
            func lookupTasks(ids: [UUID]) async throws -> [TaskStore.TaskRecord] {
                await counter.increment()
                return try await inner.lookupTasks(ids: ids)
            }
        }

        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "Flat task one")
        _ = try await tasks.create(title: "Flat task two")
        _ = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let builder = WidgetSnapshotBuilder(
            smartFilterStore: filters,
            taskLookup: CountingLookup(inner: tasks, counter: counter),
            snapshotStore: snapStore
        )
        await builder.regenerate()

        #expect(await counter.count == 0)
    }
}
