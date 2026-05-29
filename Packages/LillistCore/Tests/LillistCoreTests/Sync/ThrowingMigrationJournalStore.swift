import Foundation
@testable import LillistCore

/// Decorator over a `MigrationJournalStore` that throws on the Nth
/// `write` so tests can prove the coordinator's secondary catch-write
/// failure does not mask the *original* error (sync-3).
final class ThrowingMigrationJournalStore: MigrationJournalStore, @unchecked Sendable {
    private let underlying: MigrationJournalStore
    private let lock = NSLock()
    private var writeCount = 0
    private let throwOnWrite: Int

    /// - Parameter throwOnWrite: 1-based index of the `write` call that
    ///   should throw. Use `Int.max` to never throw.
    init(underlying: MigrationJournalStore, throwOnWrite: Int) {
        self.underlying = underlying
        self.throwOnWrite = throwOnWrite
    }

    func read() throws -> MigrationJournal { try underlying.read() }

    func write(_ journal: MigrationJournal) throws {
        lock.lock()
        writeCount += 1
        let shouldThrow = writeCount == throwOnWrite
        lock.unlock()
        if shouldThrow {
            throw LillistError.storeUnavailable(reason: "journal write \(throwOnWrite) failed (test)")
        }
        try underlying.write(journal)
    }

    func clear() throws { try underlying.clear() }
}
