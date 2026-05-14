import Foundation
import LillistCore

/// Shared helpers for App Intent `perform()` bodies.
enum IntentSupport {
    /// Constructs a `PersistenceController` against the App-Group-shared
    /// SQLite store so the intent sees the same data the main app sees.
    static func makePersistence() async throws -> PersistenceController {
        let config: StoreConfiguration
        if let group = StoreConfiguration.appGroupOnDisk(groupID: "group.io.mikeydotio.Lillist") {
            config = group
        } else {
            config = try StoreConfiguration.defaultOnDisk
        }
        return try await PersistenceController(configuration: config)
    }
}
