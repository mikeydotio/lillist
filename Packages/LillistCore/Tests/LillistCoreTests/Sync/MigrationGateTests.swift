import Testing
import Foundation
@testable import LillistCore

@Suite("MigrationGate")
struct MigrationGateTests {
    @Test("Idle journal + iCloudSync mode → proceed")
    func idleProceeds() async {
        let journal = InMemoryMigrationJournalStore()
        let modeStore = SyncModeStore(suiteName: "MigrationGateTests-\(UUID().uuidString)")
        await modeStore.setMode(.iCloudSync)
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        let decision = await gate.evaluate()
        #expect(decision == .proceed(mode: .iCloudSync))
    }

    @Test("Idle journal + LocalOnly mode → proceed")
    func idleProceedsLocal() async {
        let journal = InMemoryMigrationJournalStore()
        let modeStore = SyncModeStore(suiteName: "MigrationGateTests-\(UUID().uuidString)")
        await modeStore.setMode(.localOnly)
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        let decision = await gate.evaluate()
        #expect(decision == .proceed(mode: .localOnly))
    }

    @Test("Non-idle journal aborts with a user-facing message")
    func nonIdleAborts() async {
        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(state: .preparing, operation: .replaceLocalWithICloud))
        let modeStore = SyncModeStore(suiteName: "MigrationGateTests-\(UUID().uuidString)")
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        let decision = await gate.evaluate()
        if case .abort(let message) = decision {
            #expect(message.contains("Sync settings"))
        } else {
            Issue.record("Expected abort decision, got \(decision)")
        }
    }

    @Test("Failed-state journal also aborts")
    func failedAborts() async {
        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(state: .failed, failureReason: "test"))
        let modeStore = SyncModeStore(suiteName: "MigrationGateTests-\(UUID().uuidString)")
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        let decision = await gate.evaluate()
        if case .abort = decision {} else {
            Issue.record("Expected abort, got \(decision)")
        }
    }
}
