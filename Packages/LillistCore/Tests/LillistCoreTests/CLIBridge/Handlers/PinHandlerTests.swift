import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.PinHandler")
struct PinHandlerTests {
    @Test("Pins a task")
    func pins() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.PinHandler.pin(token: id.uuidString, persistence: p)
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.isPinned == true)
    }

    @Test("Unpins a task")
    func unpins() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.PinHandler.pin(token: id.uuidString, persistence: p)
        try await CLIBridge.PinHandler.unpin(token: id.uuidString, persistence: p)
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.isPinned == false)
    }
}
