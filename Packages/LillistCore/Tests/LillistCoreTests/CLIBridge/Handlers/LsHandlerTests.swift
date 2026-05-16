import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.LsHandler")
struct LsHandlerTests {
    @Test("Returns all non-trashed non-closed tasks by default")
    func defaultsExcludeTrashAndClosed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let live = try await tasks.create(title: "Live")
        let dead = try await tasks.create(title: "Dead")
        try await tasks.softDelete(id: dead)
        let done = try await tasks.create(title: "Done")
        try await tasks.transition(id: done, to: .closed)
        let results = try await CLIBridge.LsHandler.run(
            flags: CLIBridge.FilterFlags(),
            savedFilterName: nil,
            sort: .createdAt,
            persistence: p,
            now: Date(),
            calendar: Calendar.current
        )
        #expect(results.map(\.id).contains(live))
        #expect(results.map(\.id).contains(dead) == false)
        // Default flags don't filter by status; only trash is excluded by the
        // implicit predicate. Closed tasks are returned by default.
        #expect(results.map(\.id).contains(done))
    }

    @Test("Filter on status excludes closed tasks")
    func statusFilterExcludesClosed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let open = try await tasks.create(title: "Open")
        let done = try await tasks.create(title: "Done")
        try await tasks.transition(id: done, to: .closed)
        var flags = CLIBridge.FilterFlags()
        flags.statuses = [.todo, .started, .blocked]
        let results = try await CLIBridge.LsHandler.run(
            flags: flags, savedFilterName: nil, sort: .createdAt,
            persistence: p, now: Date(), calendar: .current
        )
        #expect(results.map(\.id).contains(open))
        #expect(results.map(\.id).contains(done) == false)
    }

    @Test("Filter on tag returns only tagged tasks")
    func tagFilter() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let a = try await tasks.create(title: "A")
        let b = try await tasks.create(title: "B")
        let tagID = try await tags.create(name: "Work")
        try await tasks.assignTag(taskID: a, tagID: tagID)
        var flags = CLIBridge.FilterFlags()
        flags.tags = ["Work"]
        let results = try await CLIBridge.LsHandler.run(
            flags: flags, savedFilterName: nil, sort: .createdAt,
            persistence: p, now: Date(), calendar: .current
        )
        #expect(results.map(\.id).contains(a))
        #expect(results.map(\.id).contains(b) == false)
    }

    @Test("Sort by title returns alphabetical")
    func sortTitle() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        _ = try await tasks.create(title: "B")
        _ = try await tasks.create(title: "A")
        _ = try await tasks.create(title: "C")
        let results = try await CLIBridge.LsHandler.run(
            flags: CLIBridge.FilterFlags(), savedFilterName: nil, sort: .title,
            persistence: p, now: Date(), calendar: .current
        )
        #expect(results.map(\.title) == ["A", "B", "C"])
    }

    @Test("Ls result surfaces seriesID for recurring tasks")
    func lsSurfacesSeriesID() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let series = SeriesStore(persistence: persistence)
        let taskID = try await tasks.create(title: "recurring")
        let seriesID = try await series.create(
            fromSeedTask: taskID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )
        let records = try await CLIBridge.LsHandler.run(
            flags: CLIBridge.FilterFlags(),
            savedFilterName: nil,
            sort: .createdAt,
            persistence: persistence,
            now: Date(),
            calendar: .current
        )
        let recurring = records.first { $0.id == taskID }
        #expect(recurring?.seriesID == seriesID)
    }

    @Test("Ls JSON round-trips byte-for-byte")
    func lsJSONRoundtrip() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "A")
        let records = try await CLIBridge.LsHandler.run(
            flags: CLIBridge.FilterFlags(), savedFilterName: nil, sort: .createdAt,
            persistence: p, now: Date(), calendar: .current
        )
        let json = try CLIBridge.TaskRenderer.json(records)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let dtos = try dec.decode([CLIBridge.TaskRenderer.TaskDTO].self, from: json)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        enc.dateEncodingStrategy = .iso8601
        let again = try enc.encode(dtos)
        #expect(json == again)
    }
}
