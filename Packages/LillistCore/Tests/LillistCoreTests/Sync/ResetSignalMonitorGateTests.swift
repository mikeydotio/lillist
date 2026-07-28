import Testing
import Foundation
@testable import LillistCore

/// `S11`: `ResetSignalMonitor`'s automatic peer-reset application must
/// respect the shared `DestructiveOpGate` — a reset arriving mid-migration
/// must wait or stay pending, never interleave. Unlike `MigrationCoordinator`
/// and `DataStoreResetService`, `ResetSignalMonitor` itself needed NO code
/// change to satisfy this: its existing apply/acknowledge ordering already
/// leaves a failed-to-apply event pending (not marked applied, not
/// acknowledged) for the next tick or relaunch to retry — see its own doc
/// comment. Once `DataStoreResetService` throws because the gate is held
/// (this plan's own change), that throw flows straight into the existing
/// retry-later path. These tests prove the END-TO-END pipeline — a REAL
/// `DataStoreResetService` wired as the `apply` closure exactly as
/// `AppEnvironment` wires it in production — not just the generic
/// throwing-closure case `ResetSignalMonitorTests` already covers.
@Suite("ResetSignalMonitor respects the shared DestructiveOpGate (S11)")
struct ResetSignalMonitorGateTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResetSignalGate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "ResetSignalMonitorGateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func peer(_ id: String) -> RosterEntry {
        RosterEntry(id: id, displayName: id, lastSeenAt: Self.fixedNow)
    }

    @MainActor
    private func makeGatedResetService(gate: DestructiveOpGate) -> DataStoreResetService {
        DataStoreResetService(
            host: FakePersistenceReconfigurer(initialMode: .iCloudSync),
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            destructiveOpGate: gate,
            quiesceMinQuietWindow: 0.05,
            quiesceHardTimeout: 1
        )
    }

    @Test("A reset event arriving while a migration holds the gate stays pending, not applied or acknowledged")
    @MainActor
    func resetStaysPendingWhileMigrationHoldsGate() async throws {
        let gate = DestructiveOpGate()
        // Simulate a migration already in flight, holding the gate —
        // exactly the state ResetSignalMonitor's checkAndApply() could
        // observe if a peer's reset broadcast arrives mid-migration.
        try gate.acquire(for: .migration(.disableNow))

        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = ResetControlEvent(
            kind: .resetToEmpty, senderDeviceID: "device-A",
            senderDisplayName: "Nephele", requestedAt: Self.fixedNow
        )
        inbox.send(e, to: [peer("device-B")])

        let resetService = makeGatedResetService(gate: gate)
        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { [resetService] _ in
            try await resetService.resetAndRedownload()
        }

        await monitor.checkAndApply()

        // The gate rejected the reset (migration still holds it) — the
        // event must stay pending for the next tick, never marked
        // applied, never acknowledged. No interleaving occurred.
        #expect(applied.hasApplied(e.id) == false)
        #expect(inbox.pendingEvents(for: "device-B") == [e])

        gate.release()
    }

    @Test("Once the migration releases the gate, the next tick applies the previously-blocked reset")
    @MainActor
    func retryAppliesOnceGateFrees() async throws {
        let gate = DestructiveOpGate()
        try gate.acquire(for: .migration(.disableNow))

        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = ResetControlEvent(
            kind: .resetToEmpty, senderDeviceID: "device-A",
            senderDisplayName: "Nephele", requestedAt: Self.fixedNow
        )
        inbox.send(e, to: [peer("device-B")])

        let resetService = makeGatedResetService(gate: gate)
        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { [resetService] _ in
            try await resetService.resetAndRedownload()
        }

        // First tick: blocked, stays pending.
        await monitor.checkAndApply()
        #expect(applied.hasApplied(e.id) == false)

        // The migration finishes and releases the gate.
        gate.release()

        // Second tick (the next notification, or a relaunch catch-up
        // pass): the reset now runs for real and the event is consumed.
        await monitor.checkAndApply()
        #expect(applied.hasApplied(e.id))
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }
}
