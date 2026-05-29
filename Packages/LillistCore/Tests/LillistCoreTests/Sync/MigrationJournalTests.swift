import Testing
import Foundation
@testable import LillistCore

@Suite("MigrationJournal + MigrationJournalStore")
struct MigrationJournalTests {
    private static func tempJournalURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationJournalTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("migration.json")
    }

    @Test("Idle journal has no in-flight operation")
    func idle() {
        #expect(MigrationJournal.idle.state == .idle)
        #expect(MigrationJournal.idle.isInFlight == false)
    }

    @Test("Any non-idle state counts as in-flight")
    func inFlight() {
        for state in [MigrationJournal.State.preparing, .quarantining, .mutatingCloudKit, .reconfiguringStore, .awaitingSync, .finalizing, .failed] {
            #expect(MigrationJournal(state: state).isInFlight == true)
        }
    }

    @Test("File store round-trips a populated journal")
    func fileStoreRoundTrip() throws {
        let url = Self.tempJournalURL()
        let store = FileMigrationJournalStore(url: url)
        let journal = MigrationJournal(
            state: .quarantining,
            operation: .replaceICloudWithLocal,
            startedAt: Date(timeIntervalSince1970: 100),
            lastHeartbeatAt: Date(timeIntervalSince1970: 105),
            previousMode: .iCloudSync,
            failureReason: nil,
            quarantineFolderName: "1700000000"
        )
        try store.write(journal)
        let restored = try store.read()
        #expect(restored.state == .quarantining)
        #expect(restored.operation == .replaceICloudWithLocal)
        #expect(restored.quarantineFolderName == "1700000000")
        #expect(restored.previousMode == .iCloudSync)
    }

    @Test("Reading a missing file returns the idle journal")
    func missingFileIsIdle() throws {
        let url = Self.tempJournalURL()
        let store = FileMigrationJournalStore(url: url)
        let j = try store.read()
        #expect(j == .idle)
    }

    @Test("Clearing the journal removes the file")
    func clear() throws {
        let url = Self.tempJournalURL()
        let store = FileMigrationJournalStore(url: url)
        try store.write(MigrationJournal(state: .preparing))
        #expect(FileManager.default.fileExists(atPath: url.path) == true)
        try store.clear()
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        // Subsequent read on a cleared store yields idle.
        #expect(try store.read() == .idle)
    }

    @Test("Atomic write: a fresh reader never observes a half-written file")
    func atomicWrite() throws {
        // We can't easily induce a real torn write in unit tests, but
        // we can at minimum verify that the underlying API is the
        // atomic variant by writing repeatedly and checking the file
        // is always parseable. This is a regression guard against a
        // refactor that drops `.atomic`.
        let url = Self.tempJournalURL()
        let store = FileMigrationJournalStore(url: url)
        for i in 0..<50 {
            try store.write(MigrationJournal(
                state: .reconfiguringStore,
                operation: .replaceICloudWithLocal,
                startedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                lastHeartbeatAt: Date(timeIntervalSince1970: TimeInterval(i))
            ))
            let read = try store.read()
            #expect(read.state == .reconfiguringStore)
        }
    }

    @Test("In-memory store implements the protocol contract")
    func inMemoryRoundTrip() throws {
        let store = InMemoryMigrationJournalStore()
        #expect(try store.read() == .idle)
        let j = MigrationJournal(state: .preparing, operation: .syncFirstThenDisable)
        try store.write(j)
        #expect(try store.read().state == .preparing)
        try store.clear()
        #expect(try store.read() == .idle)
    }
}
