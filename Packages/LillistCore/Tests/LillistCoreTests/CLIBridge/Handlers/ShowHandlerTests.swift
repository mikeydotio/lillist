import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.ShowHandler")
struct ShowHandlerTests {
    @Test("Resolves and returns task + journal entries")
    func showsBasics() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journal = JournalStore(persistence: p)
        let id = try await tasks.create(title: "Buy milk")
        _ = try await journal.appendNote(taskID: id, body: "Hello")
        let result = try await CLIBridge.ShowHandler.run(
            token: "Buy milk",
            persistence: p
        )
        #expect(result.task.id == id)
        #expect(result.journal.count == 1)
    }

    @Test("Notes a partial match (pickedSilently flag)")
    func partialMatchFlagged() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        _ = try await tasks.create(title: "Buy milk for tomorrow")
        let result = try await CLIBridge.ShowHandler.run(
            token: "milk",
            persistence: p
        )
        #expect(result.pickedSilently == true)
    }

    @Test("Show JSON round-trips for a single task")
    func showJSONRoundtrip() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Solo")
        let result = try await CLIBridge.ShowHandler.run(token: id.uuidString, persistence: p)
        let json = try CLIBridge.TaskRenderer.json([result.task])
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let dtos = try dec.decode([CLIBridge.TaskRenderer.TaskDTO].self, from: json)
        #expect(dtos.count == 1)
        #expect(dtos[0].title == "Solo")
    }
}
