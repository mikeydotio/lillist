import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.SearchHandler")
struct SearchHandlerTests {
    @Test("Searches by title substring")
    func titleSubstring() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Buy milk")
        _ = try await TaskStore(persistence: p).create(title: "Walk dog")
        let results = try await CLIBridge.SearchHandler.run(query: "milk", scopeToken: nil, persistence: p)
        #expect(results.contains { $0.id == id })
        #expect(results.count == 1)
    }

    @Test("Scoped search restricts to descendants")
    func scopedSearch() async throws {
        let p = try await TestStore.make()
        let parent = try await TaskStore(persistence: p).create(title: "Project")
        let inside = try await TaskStore(persistence: p).create(title: "task with milk", parent: parent)
        _ = try await TaskStore(persistence: p).create(title: "another milk task")
        let results = try await CLIBridge.SearchHandler.run(query: "milk", scopeToken: parent.uuidString, persistence: p)
        #expect(results.map(\.id) == [inside])
    }
}
