import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.CountHandler")
struct CountHandlerTests {
    @Test("Counts non-trashed by default")
    func defaultCount() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "A")
        _ = try await TaskStore(persistence: p).create(title: "B")
        let n = try await CLIBridge.CountHandler.run(
            flags: CLIBridge.FilterFlags(), savedFilterName: nil,
            persistence: p, now: Date(), calendar: .current
        )
        #expect(n == 2)
    }
}
