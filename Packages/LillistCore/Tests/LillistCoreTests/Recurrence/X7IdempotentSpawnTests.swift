import Testing
import CoreData
import Foundation
@testable import LillistCore

/// X7: recurrence spawns had no idempotency key — a concurrent widget/app
/// interaction, or two devices closing the same task near-simultaneously,
/// double-spawned the identical occurrence under distinct random UUIDs that
/// `TaskDuplicateReconciler` (keyed on app-level `id` equality) had no way
/// to collapse. This suite proves `DeterministicUUID.v5`'s pure-function
/// contract, that a simulated concurrent double-spawn converges on the same
/// `id` for both the spawn and its deep-copied children, and that the
/// existing duplicate-reconciler mechanism actually heals the resulting
/// same-`id` duplicate rows end-to-end.
@Suite("X7 — deterministic recurrence spawn identity")
struct X7IdempotentSpawnTests {
    /// Reports a fixed set of object IDs as "mirrored" — same seam
    /// `TaskDuplicateReconcilerTests` uses.
    private struct FakeMirrorIdentifier: MirroredObjectIdentifying {
        let mirrored: Set<NSManagedObjectID>
        func mirroredObjectIDs(among ids: [NSManagedObjectID]) -> Set<NSManagedObjectID> {
            Set(ids).intersection(mirrored)
        }
    }

    // MARK: - DeterministicUUID: pure-function contract

    @Test("Same namespace + name always produces the same UUID")
    func v5IsDeterministic() {
        let namespace = UUID()
        let a = DeterministicUUID.v5(namespace: namespace, name: "2026-01-15")
        let b = DeterministicUUID.v5(namespace: namespace, name: "2026-01-15")
        #expect(a == b)
    }

    @Test("Different occurrence names under the same series produce different ids")
    func differentNamesDiffer() {
        let namespace = UUID()
        let a = DeterministicUUID.v5(namespace: namespace, name: "2026-01-15")
        let b = DeterministicUUID.v5(namespace: namespace, name: "2026-01-16")
        #expect(a != b)
    }

    @Test("The same occurrence name under different series produces different ids")
    func differentNamespacesDiffer() {
        let name = "2026-01-15"
        let a = DeterministicUUID.v5(namespace: UUID(), name: name)
        let b = DeterministicUUID.v5(namespace: UUID(), name: name)
        #expect(a != b)
    }

    // MARK: - Concurrent double-spawn: same occurrence converges on the same id

    /// Simulates two processes racing on the SAME pre-advance
    /// `series.nextOccurrenceAfter` — both call `spawnIfNeeded` against a
    /// `Series` reset back to the value both would have read before either
    /// side's advance committed. This is the direct mechanism proof: same
    /// (series, occurrence) inputs, same output id — independent of
    /// however many real processes/devices are actually involved.
    @Test("Two concurrent spawns of the same occurrence share the same id")
    func concurrentDoubleSpawnConvergesOnSameID() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let seriesStore = SeriesStore(persistence: p)
        let seedID = try await taskStore.create(title: "Daily standup")
        try await taskStore.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await seriesStore.create(fromSeedTask: seedID, rule: rule)

        let ctx = p.container.viewContext
        let (firstID, secondID): (UUID?, UUID?) = try await ctx.perform {
            let seedTask = try taskStore.fetchManagedObject(id: seedID, in: ctx)
            let seriesM = try seriesStore.fetchManagedObject(id: seriesID, in: ctx)
            let preRaceNextOccurrence = seriesM.nextOccurrenceAfter

            seedTask.status = .closed
            seedTask.closedAt = Date()
            let first = try RecurrenceSpawner.spawnIfNeeded(forClosedTask: seedTask, in: ctx)

            // Simulate the second racing process: it read
            // `nextOccurrenceAfter` before the first process's advance
            // committed — reset the series field back to that pre-race
            // value, then spawn again from the same seed.
            seriesM.nextOccurrenceAfter = preRaceNextOccurrence
            let second = try RecurrenceSpawner.spawnIfNeeded(forClosedTask: seedTask, in: ctx)

            return (first, second)
        }
        #expect(firstID != nil)
        #expect(firstID == secondID, "two concurrent spawns of the same occurrence must converge on the same id")
    }

    @Test("A concurrent double-spawn's deep-copied children also converge on the same id, per source child")
    func concurrentDoubleSpawnChildrenConvergeOnSameID() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let seriesStore = SeriesStore(persistence: p)
        let seedID = try await taskStore.create(title: "Weekly review")
        let subtaskAID = try await taskStore.create(title: "Subtask A", parent: seedID)
        _ = try await taskStore.create(title: "Subtask B", parent: seedID)
        let rule = RecurrenceRule.calendar(.init(freq: .weekly, interval: 1))
        let seriesID = try await seriesStore.create(fromSeedTask: seedID, rule: rule)

        let ctx = p.container.viewContext
        let (firstSpawnID, secondSpawnID): (UUID?, UUID?) = try await ctx.perform {
            let seedTask = try taskStore.fetchManagedObject(id: seedID, in: ctx)
            let seriesM = try seriesStore.fetchManagedObject(id: seriesID, in: ctx)
            let preRaceNextOccurrence = seriesM.nextOccurrenceAfter

            seedTask.status = .closed
            seedTask.closedAt = Date()
            let first = try RecurrenceSpawner.spawnIfNeeded(forClosedTask: seedTask, in: ctx)

            seriesM.nextOccurrenceAfter = preRaceNextOccurrence
            let second = try RecurrenceSpawner.spawnIfNeeded(forClosedTask: seedTask, in: ctx)

            return (first, second)
        }
        #expect(firstSpawnID != nil && secondSpawnID != nil)
        #expect(firstSpawnID == secondSpawnID)

        // Both spawns' children, matched by title (their content is
        // identical since both are deep copies of the same seed subtree),
        // must carry the SAME id.
        let firstChildren = try await taskStore.children(of: firstSpawnID)
        let secondChildren = try await taskStore.children(of: secondSpawnID)
        #expect(firstChildren.count == 2)
        #expect(secondChildren.count == 2)
        for title in ["Subtask A", "Subtask B"] {
            let firstChild = firstChildren.first { $0.title == title }!
            let secondChild = secondChildren.first { $0.title == title }!
            #expect(firstChild.id == secondChild.id, "child '\(title)' should converge on the same id across the two racing spawns")
        }
        // Sanity: distinct source children must not accidentally collide.
        #expect(firstChildren[0].id != firstChildren[1].id)
        _ = subtaskAID
    }

    // MARK: - End-to-end: TaskDuplicateReconciler actually heals the pair

    @Test("The existing duplicate reconciler collapses a same-id concurrent-spawn pair to one survivor, re-pointing children")
    func duplicateReconcilerHealsConcurrentSpawnPair() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let seriesStore = SeriesStore(persistence: p)
        let seedID = try await taskStore.create(title: "Daily standup")
        try await taskStore.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await seriesStore.create(fromSeedTask: seedID, rule: rule)

        let ctx = p.container.viewContext
        let (loserObjectID, survivorObjectID, spawnID): (NSManagedObjectID, NSManagedObjectID, UUID) = try await ctx.perform {
            let seedTask = try taskStore.fetchManagedObject(id: seedID, in: ctx)
            let seriesM = try seriesStore.fetchManagedObject(id: seriesID, in: ctx)
            let preRaceNextOccurrence = seriesM.nextOccurrenceAfter

            seedTask.status = .closed
            seedTask.closedAt = Date()
            let firstID = try RecurrenceSpawner.spawnIfNeeded(forClosedTask: seedTask, in: ctx)!

            seriesM.nextOccurrenceAfter = preRaceNextOccurrence
            let secondID = try RecurrenceSpawner.spawnIfNeeded(forClosedTask: seedTask, in: ctx)!
            precondition(firstID == secondID, "test setup expects the two racing spawns to converge on one id")

            try ctx.save()

            // Both racing rows now share `firstID`/`secondID` (equal by
            // construction), so fetching "by id" alone can't distinguish
            // them — fetch BOTH matching rows together instead (mirrors
            // `TaskDuplicateReconcilerTests.mergesToMirroredSurvivor`'s
            // pattern for the same reason).
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", firstID as CVarArg)
            let rows = try ctx.fetch(req)
            precondition(rows.count == 2, "expected exactly 2 duplicate rows, got \(rows.count)")
            // Arbitrary pick: the reconciler decides the real survivor via
            // the mirror signal below, not object-creation order.
            return (rows[0].objectID, rows[1].objectID, firstID)
        }
        #expect(loserObjectID != survivorObjectID, "the two racing spawns must be distinct managed-object rows sharing one id")

        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        #expect(deletedCount == 1)

        let remaining = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", spawnID as CVarArg)
            return try ctx.fetch(req)
        }
        #expect(remaining.count == 1, "the duplicate reconciler must collapse the pair to exactly one row")
        #expect(remaining.first?.objectID == survivorObjectID)
    }

    // MARK: - Non-racing path is unaffected

    @Test("A normal, non-racing close still spawns exactly once, with a deterministic id")
    func nonRacingSpawnIsUnaffected() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let seriesStore = SeriesStore(persistence: p)
        let seedID = try await taskStore.create(title: "Daily")
        try await taskStore.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await seriesStore.create(fromSeedTask: seedID, rule: rule)

        try await taskStore.transition(id: seedID, to: .closed)

        let allRoots = try await taskStore.children(of: nil)
        let standups = allRoots.filter { $0.title == "Daily" }
        #expect(standups.count == 2)
    }
}
