import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.Resolver.resolveAll")
struct ResolveAllTests {
    private func makeStore() async throws -> (PersistenceController, TaskStore) {
        let p = try await TestStore.make()
        return (p, TaskStore(persistence: p))
    }

    @Test("resolveAll returns one resolution per token, in order")
    func resolvesAllInOrder() async throws {
        let (p, store) = try await makeStore()
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: [a.uuidString, b.uuidString],
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        #expect(resolutions.map(\.id) == [a, b])
    }

    @Test("resolveAll throws on the first unresolvable token before returning anything")
    func throwsOnBadToken() async throws {
        let (p, store) = try await makeStore()
        let a = try await store.create(title: "Alpha")
        await #expect(throws: LillistError.notFound) {
            _ = try await CLIBridge.Resolver.resolveAll(
                tokens: [a.uuidString, "00000000-0000-0000-0000-0000000000ff"],
                scope: .anywhereIncludingClosed,
                destructiveness: .destructive,
                persistence: p
            )
        }
    }

    @Test("resolveAll surfaces a destructive partial-match refusal")
    func throwsOnDestructivePartial() async throws {
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Buy groceries weekly")
        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.Resolver.resolveAll(
                tokens: ["groc"],
                scope: .anywhere,
                destructiveness: .destructive,
                persistence: p
            )
        }
    }
}
