import Foundation

/// Reads and writes the `ReseedJournal` to a JSON file. See
/// `ReseedJournal`'s header comment for why this is a separate type from
/// `MigrationJournalStore` rather than a reused one.
///
/// Implementations must guarantee atomic writes — a crash between the
/// write's temp-file creation and its rename-install must never leave a
/// half-written file for the next launch to trip over.
public protocol ReseedJournalStore: Sendable {
    func read() throws -> ReseedJournal
    func write(_ journal: ReseedJournal) throws
    func clear() throws
}

/// File-backed implementation, written with
/// `Data.write(to:options:.atomic)` — mirrors `FileMigrationJournalStore`.
public struct FileReseedJournalStore: ReseedJournalStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Build a store rooted at the App Group container's
    /// `Lillist/reseed.json`. Returns `nil` if the App Group is not
    /// reachable.
    public init?(appGroupID: String) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        let dir = container.appendingPathComponent("Lillist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("reseed.json")
    }

    public func read() throws -> ReseedJournal {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .idle
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return .idle }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReseedJournal.self, from: data)
    }

    public func write(_ journal: ReseedJournal) throws {
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

/// In-memory variant for unit tests and as the harmless default for
/// production callers that don't wire a durable store — mirrors
/// `InMemoryMigrationJournalStore`.
public final class InMemoryReseedJournalStore: ReseedJournalStore, @unchecked Sendable {
    private var current: ReseedJournal
    private let lock = NSLock()

    public init(initial: ReseedJournal = .idle) {
        self.current = initial
    }

    public func read() throws -> ReseedJournal {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func write(_ journal: ReseedJournal) throws {
        lock.lock()
        defer { lock.unlock() }
        current = journal
    }

    public func clear() throws {
        try write(.idle)
    }
}
