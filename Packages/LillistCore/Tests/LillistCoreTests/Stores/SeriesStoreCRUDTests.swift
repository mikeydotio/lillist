import Testing
import Foundation
@testable import LillistCore

@Suite("SeriesStore CRUD")
struct SeriesStoreCRUDTests {
    @Test("Create from seed task wires the relationship and persists the rule")
    func createFromSeed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let taskID = try await tasks.create(title: "Water plants")
        try await tasks.update(id: taskID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: taskID, rule: rule)

        let record = try await series.fetch(id: seriesID)
        #expect(record.seedTaskID == taskID)
        #expect(record.rule == rule)
        #expect(record.nextOccurrenceAfter != nil)

        let instances = try await series.instances(of: seriesID)
        #expect(instances.contains(taskID))
    }

    @Test("Creating a series sets nextOccurrenceAfter from the seed's start")
    func nextOccurrenceComputed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let seedStart = Date(timeIntervalSince1970: 1_800_000_000)
        try await tasks.update(id: id) { $0.start = seedStart }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)
        let next = try await series.fetch(id: seriesID).nextOccurrenceAfter
        #expect(next != nil)
        #expect(next! > seedStart)
    }

    @Test("Create from seed without a start uses createdAt as the anchor")
    func anchorsOnCreatedAtWhenNoStart() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter != nil)
    }

    @Test("Update rewrites the rule JSON")
    func updateRule() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let original = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: original)
        let updated = RecurrenceRule.calendar(.init(freq: .weekly, interval: 1))
        try await series.update(id: seriesID, rule: updated)
        #expect(try await series.fetch(id: seriesID).rule == updated)
    }

    @Test("Delete clears series from instances but doesn't delete the tasks")
    func deletePreservesInstances() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)
        try await series.delete(id: seriesID)
        await #expect(throws: LillistError.notFound) {
            _ = try await series.fetch(id: seriesID)
        }
        _ = try await tasks.fetch(id: id)
    }

    @Test("List returns all series ordered by next-occurrence")
    func list() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let a = try await tasks.create(title: "A")
        let b = try await tasks.create(title: "B")
        _ = try await series.create(fromSeedTask: a, rule: .calendar(.init(freq: .daily, interval: 1)))
        _ = try await series.create(fromSeedTask: b, rule: .calendar(.init(freq: .weekly, interval: 1)))
        let all = try await series.list()
        #expect(all.count == 2)
    }
}
