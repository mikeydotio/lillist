import Testing
import Foundation
@testable import LillistCore

@Suite("SeriesStore fork")
struct SeriesStoreForkTests {
    @Test("Forking from a non-seed instance creates a new series")
    func forkCreatesNewSeries() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let originalSeriesID = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!

        let newSeriesID = try await series.forkFutureFromInstance(instanceID: spawn.id)

        #expect(newSeriesID != originalSeriesID)
        let newRec = try await series.fetch(id: newSeriesID)
        #expect(newRec.seedTaskID == spawn.id)
        #expect(newRec.rule == rule)
    }

    @Test("Forking preserves the old series and its existing instances")
    func forkPreservesOldSeries() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let originalID = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!
        _ = try await series.forkFutureFromInstance(instanceID: spawn.id)

        let oldRec = try await series.fetch(id: originalID)
        #expect(oldRec.seedTaskID == seedID)
        let oldInstances = try await series.instances(of: originalID)
        #expect(oldInstances.contains(seedID))
    }

    @Test("Forking moves the forked instance to the new series")
    func forkMovesInstance() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let originalID = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)
        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!

        let newID = try await series.forkFutureFromInstance(instanceID: spawn.id)

        let oldInstances = try await series.instances(of: originalID)
        let newInstances = try await series.instances(of: newID)
        #expect(oldInstances.contains(spawn.id) == false)
        #expect(newInstances.contains(spawn.id))
    }

    @Test("Forking from the seed itself throws validationFailed")
    func cannotForkFromSeed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: id, rule: rule)
        await #expect(throws: LillistError.self) {
            _ = try await series.forkFutureFromInstance(instanceID: id)
        }
    }

    @Test("Forking from a task with no series throws validationFailed")
    func cannotForkNonInstance() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        await #expect(throws: LillistError.self) {
            _ = try await series.forkFutureFromInstance(instanceID: id)
        }
    }

    @Test("Future spawns from the new series use the forked instance's start")
    func newSeriesSpawnsFromFork() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!
        let newSeriesID = try await series.forkFutureFromInstance(instanceID: spawn.id)

        let newStart = Date(timeIntervalSince1970: 2_000_000_000)
        try await tasks.update(id: spawn.id) { $0.start = newStart }
        try await series.update(id: newSeriesID, rule: rule)

        let next = try await series.fetch(id: newSeriesID).nextOccurrenceAfter
        #expect(next != nil)
        #expect(next! > newStart)
    }
}
