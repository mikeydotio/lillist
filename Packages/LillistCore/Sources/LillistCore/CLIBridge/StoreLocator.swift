import Foundation

extension CLIBridge {
    /// Locates the Lillist Core Data store for CLI / App Intents access.
    ///
    /// The CLI does not own the store path; it inherits it from the macOS
    /// app's app-group container so both clients see the same data. If
    /// the container does not exist (app never installed / never run),
    /// the locator throws `LillistError.storeUnavailable` with a friendly
    /// install pointer.
    public enum StoreLocator {
        public static let appGroupIdentifier = "group.io.mikeydotio.Lillist"

        public static let sqliteFilename = "Lillist.sqlite"

        public static func openInMemory() async throws -> PersistenceController {
            try await PersistenceController(configuration: .inMemory)
        }

        public static func openOnDisk(at url: URL) async throws -> PersistenceController {
            try await PersistenceController(configuration: .onDisk(url: url))
        }

        public static func openAppGroup(identifier: String = appGroupIdentifier) async throws -> PersistenceController {
            let fm = FileManager.default
            guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw LillistError.storeUnavailable(reason: "App group container '\(identifier)' is not available. Install the Lillist macOS app from the App Store or via Homebrew, then run it at least once.")
            }
            let dir = container
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Lillist", isDirectory: true)
            let url = dir.appendingPathComponent(sqliteFilename)
            guard fm.fileExists(atPath: url.path) else {
                throw LillistError.storeUnavailable(reason: "Lillist store not found at \(url.path). Run the Lillist app at least once to initialize the store.")
            }
            return try await PersistenceController(configuration: .onDisk(url: url))
        }
    }
}
