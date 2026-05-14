import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.StatusHandler")
struct StatusHandlerTests {
    @Test("Transitions to started for fuzzy match")
    func started() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Demo")
        try await CLIBridge.StatusHandler.run(
            token: "Demo", to: .started, note: nil, persistence: p
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.status == .started)
    }

    @Test("Transition to closed requires exact match for fuzzy token")
    func closedRequiresExact() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "Buy stuff at the store")
        await #expect(throws: LillistError.self) {
            try await CLIBridge.StatusHandler.run(
                token: "stuff", to: .closed, note: nil, persistence: p
            )
        }
    }

    @Test("Closed transition accepts UUID")
    func closedAcceptsUUID() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Demo")
        try await CLIBridge.StatusHandler.run(
            token: id.uuidString, to: .closed, note: nil, persistence: p
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.status == .closed)
    }

    @Test("Optional note appended after transition")
    func noteAppended() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Demo")
        try await CLIBridge.StatusHandler.run(
            token: id.uuidString, to: .blocked, note: "waiting on QA", persistence: p
        )
        let entries = try await JournalStore(persistence: p).entries(forTask: id)
        #expect(entries.contains { $0.body == "waiting on QA" })
    }
}
