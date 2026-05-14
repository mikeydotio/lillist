import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.EvalHandler")
struct EvalHandlerTests {
    @Test("Trivial group matches all non-trashed tasks")
    func trivialAll() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "A")
        _ = try await TaskStore(persistence: p).create(title: "B")
        let matched = try await CLIBridge.EvalHandler.run(
            groupJSON: "{\"combinator\":\"all\",\"predicates\":[]}",
            persistence: p, now: Date(), calendar: .current
        )
        #expect(matched.count == 2)
    }

    @Test("Invalid JSON throws validationFailed")
    func invalidJSON() async throws {
        let p = try await TestStore.make()
        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.EvalHandler.run(groupJSON: "not json", persistence: p, now: Date(), calendar: .current)
        }
    }
}
