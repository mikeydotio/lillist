import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore recurrence spawn")
struct TaskStoreRecurrenceSpawnTests {
    @Test("Closing a recurring instance spawns the next one")
    func spawnsOnClose() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily standup")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        try await tasks.transition(id: seedID, to: .closed)

        let allRoots = try await tasks.children(of: nil)
        let standups = allRoots.filter { $0.title == "Daily standup" }
        #expect(standups.count == 2)
        let openCount = standups.filter { $0.status == .todo }.count
        #expect(openCount == 1)
    }

    @Test("Closing a non-recurring task does NOT spawn")
    func noSpawnForNonRecurring() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "One-shot")
        try await tasks.transition(id: id, to: .closed)
        let all = try await tasks.children(of: nil)
        #expect(all.count == 1)
    }

    @Test("Re-opening a closed instance does NOT undo the spawn")
    func reopenDoesNotUndoSpawn() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        try await tasks.transition(id: seedID, to: .closed)
        try await tasks.transition(id: seedID, to: .todo)

        let allRoots = try await tasks.children(of: nil)
        #expect(allRoots.filter { $0.title == "Daily" }.count == 2)
    }

    @Test("Spawning copies the seed's children")
    func deepCopiesChildren() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Weekly review")
        _ = try await tasks.create(title: "Subtask A", parent: seedID)
        _ = try await tasks.create(title: "Subtask B", parent: seedID)
        let rule = RecurrenceRule.calendar(.init(freq: .weekly, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Weekly review" && $0.id != seedID }
        #expect(spawn != nil)
        let spawnedKids = try await tasks.children(of: spawn!.id)
        #expect(Set(spawnedKids.map(\.title)) == ["Subtask A", "Subtask B"])
    }

    @Test("Spawned instance is open (todo) regardless of seed status")
    func spawnedIsTodo() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: id, rule: rule)
        try await tasks.transition(id: id, to: .closed)
        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "T" && $0.id != id }
        #expect(spawn!.status == .todo)
    }

    @Test("Series with count=2 spawns once and then stops")
    func countLimit() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "Twice")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1, count: 2))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)

        try await tasks.transition(id: id, to: .closed)
        let afterFirst = try await tasks.children(of: nil).filter { $0.title == "Twice" }
        #expect(afterFirst.count == 2)

        let openID = afterFirst.first { $0.status == .todo }!.id
        try await tasks.transition(id: openID, to: .closed)
        let afterSecond = try await tasks.children(of: nil).filter { $0.title == "Twice" }
        #expect(afterSecond.count == 2)
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter == nil)
    }

    @Test("Trashing an instance does not consume the count budget")
    func trashedInstanceDoesNotConsumeCount() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Budgeted")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        // count=3: a count=2 series hits its budget on the very first close
        // (seed + spawn = 2 live -> nextOccurrenceAfter nil before any trash
        // can matter). count=3 leaves the series still spawning after the
        // first close, so trashing a live instance can actually free a slot.
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1, count: 3))
        let seriesID = try await series.create(fromSeedTask: seedID, rule: rule)

        // Close the seed (instance #1) -> spawns instance #2. Two live
        // instances against a budget of 3, so the series keeps a future
        // occurrence.
        try await tasks.transition(id: seedID, to: .closed)
        let afterFirst = try await tasks.children(of: nil).filter { $0.title == "Budgeted" }
        #expect(afterFirst.count == 2)
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter != nil)

        // Trash the original seed instance, leaving only instance #2 live. The
        // trashed seed must NOT count toward the count=3 budget.
        try await tasks.softDelete(id: seedID)

        // Close the surviving live instance (#2) -> spawns instance #3. Were
        // the trashed seed still counted (3 total >= 3) the series would stop
        // here; excluding it (2 live < 3) keeps a future occurrence alive.
        let liveOpenID = afterFirst.first { $0.id != seedID && $0.status == .todo }!.id
        try await tasks.transition(id: liveOpenID, to: .closed)

        // Series still has a future occurrence (budget not exhausted by the
        // trashed instance) -- this is the assertion that distinguishes the
        // fix from the bug.
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter != nil)
        // Exactly two LIVE instances exist (#2 closed + #3 todo); the trashed
        // seed is filtered out of `children(of:)`, which drops deletedAt != nil.
        let live = try await tasks.children(of: nil).filter { $0.title == "Budgeted" }
        #expect(live.count == 2)
    }

    @Test("Series with until that has passed spawns no more")
    func untilLimit() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "Bounded")
        let seedStart = Date(timeIntervalSince1970: 1_800_000_000)
        try await tasks.update(id: id) { $0.start = seedStart }
        let until = seedStart.addingTimeInterval(60)
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1, until: until))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)

        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter == nil)

        try await tasks.transition(id: id, to: .closed)
        let roots = try await tasks.children(of: nil).filter { $0.title == "Bounded" }
        #expect(roots.count == 1)
    }

    @Test("After-completion series spawns at completedAt + interval")
    func afterCompletionSpawn() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "Three days after")
        let rule = RecurrenceRule.afterCompletion(.init(interval: 86_400 * 3))
        _ = try await series.create(fromSeedTask: id, rule: rule)

        let beforeClose = Date()
        try await tasks.transition(id: id, to: .closed)

        let roots = try await tasks.children(of: nil).filter { $0.title == "Three days after" }
        #expect(roots.count == 2)
        let spawn = roots.first { $0.status == .todo }!
        let expected = beforeClose.addingTimeInterval(86_400 * 3)
        #expect(abs(spawn.start!.timeIntervalSince(expected)) < 2.0)
    }
}
