import Foundation
@testable import LillistCore

/// Convenience factory for in-memory PersistenceController instances in tests.
enum TestStore {
    static func make() async throws -> PersistenceController {
        try await PersistenceController(configuration: .inMemory)
    }
}
