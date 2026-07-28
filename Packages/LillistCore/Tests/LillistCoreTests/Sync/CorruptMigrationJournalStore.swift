import Foundation
@testable import LillistCore

/// A `MigrationJournalStore` whose `read()` always throws a
/// decode-shaped error, simulating a journal file that exists on disk
/// but failed to parse (truncated write, foreign-format contents,
/// future-version schema). Distinct from "file absent," which
/// `FileMigrationJournalStore.read()` already handles by returning
/// `.idle` without throwing — this fake exists to prove callers treat
/// the two cases differently (`S15`: undecodable must fail closed, not
/// read as `.idle`).
struct CorruptMigrationJournalStore: MigrationJournalStore {
    struct SimulatedDecodeFailure: Error {}

    func read() throws -> MigrationJournal { throw SimulatedDecodeFailure() }
    func write(_ journal: MigrationJournal) throws {}
    func clear() throws {}
}
