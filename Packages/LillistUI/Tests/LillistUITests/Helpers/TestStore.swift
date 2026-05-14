import Foundation
import LillistCore

/// In-memory factory for LillistCore stores. Mirrors the helper used in
/// LillistCoreTests but lives here so UI tests can build fixtures without
/// depending on the test bundle of another package.
@MainActor
enum TestStore {
    static func make() async throws -> PersistenceController {
        try await PersistenceController(configuration: .inMemory)
    }

    @discardableResult
    static func seed(_ p: PersistenceController) async throws -> [UUID] {
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Buy milk")
        let b = try await store.create(title: "Plan trip")
        let c = try await store.create(title: "Book flights", parent: b)
        return [a, b, c]
    }
}
