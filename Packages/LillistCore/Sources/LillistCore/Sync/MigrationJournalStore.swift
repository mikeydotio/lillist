import Foundation

/// Reads and writes the `MigrationJournal` to a JSON file in the App
/// Group container.
///
/// Implementations must guarantee atomic writes — readers from other
/// processes (Share Extension, App Intents, CLI) must never observe a
/// half-written file.
public protocol MigrationJournalStore: Sendable {
    func read() throws -> MigrationJournal
    func write(_ journal: MigrationJournal) throws
    func clear() throws
}

/// File-backed implementation, written with
/// `Data.write(to:options:.atomic)` so the file is rename-installed
/// at the destination.
public struct FileMigrationJournalStore: MigrationJournalStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Build a store rooted at the App Group container's
    /// `Lillist/migration.json`. Returns `nil` if the App Group is not
    /// reachable.
    public init?(appGroupID: String) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        let dir = container.appendingPathComponent("Lillist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("migration.json")
    }

    public func read() throws -> MigrationJournal {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .idle
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return .idle }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MigrationJournal.self, from: data)
    }

    public func write(_ journal: MigrationJournal) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(journal)
        try data.write(to: url, options: [.atomic])
    }

    public func clear() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}

/// In-memory variant for unit tests. Thread-safe via a recursive
/// lock; the protocol's sync API rules out an actor without async
/// shim layers we don't need at the call site.
public final class InMemoryMigrationJournalStore: MigrationJournalStore, @unchecked Sendable {
    private var current: MigrationJournal
    private let lock = NSLock()

    public init(initial: MigrationJournal = .idle) {
        self.current = initial
    }

    public func read() throws -> MigrationJournal {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func write(_ journal: MigrationJournal) throws {
        lock.lock()
        defer { lock.unlock() }
        current = journal
    }

    public func clear() throws {
        try write(.idle)
    }
}
