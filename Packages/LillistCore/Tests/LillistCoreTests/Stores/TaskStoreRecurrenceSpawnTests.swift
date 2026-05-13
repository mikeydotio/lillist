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
