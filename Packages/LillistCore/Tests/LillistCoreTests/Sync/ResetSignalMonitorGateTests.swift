import Testing
import Foundation
@testable import LillistCore

/// `S11`: `ResetSignalMonitor`'s user-confirmed reset application must
/// respect the shared `DestructiveOpGate` — a reset confirmed while a
/// migration holds the gate must fail and stay pending, never interleave.
/// `ResetSignalMonitor` itself needs no gate-awareness of its own: its
/// existing apply/acknowledge ordering already leaves a failed-to-apply
/// event pending (not marked applied, not acknowledged) for the next
/// confirmation to retry — see its own doc comment. Once
/// `DataStoreResetService` throws because the gate is held (a `2a`
/// change), that throw flows straight into `confirmApply()`'s existing
/// retry-later path (data-sync-hardening `S10`: `confirmApply()` is the
/// only path that ever applies anything, replacing the old auto-applying
/// `checkAndApply()` this suite originally drove directly). These tests
/// prove the END-TO-END pipeline — a REAL `DataStoreResetService` wired as
/// the `apply` closure exactly as `AppEnvironment` wires it in production —
/// not just the generic throwing-closure case `ResetSignalMonitorTests`
/// already covers.
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

    @Test("A reset confirmed while a migration holds the gate stays pending, not applied or acknowledged")
    @MainActor
    func resetStaysPendingWhileMigrationHoldsGate() async throws {
        let gate = DestructiveOpGate()
        // Simulate a migration already in flight, holding the gate —
        // exactly the state a user could confirm into if a peer's reset
        // broadcast arrives and is approved mid-migration.
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
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { [resetService] _ in
            try await resetService.resetAndRedownload()
        }

        await monitor.refreshPendingDecision()
        #expect(await monitor.pendingDecision == e)
        await #expect(throws: (any Error).self) { try await monitor.confirmApply() }

        // The gate rejected the reset (migration still holds it) — the
        // event must stay pending for the next confirmation, never marked
        // applied, never acknowledged. No interleaving occurred.
        #expect(applied.hasApplied(e.id) == false)
        #expect(inbox.pendingEvents(for: "device-B") == [e])
        #expect(await monitor.pendingDecision == e)

        gate.release()
    }

    @Test("Once the migration releases the gate, confirming again applies the previously-blocked reset")
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
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { [resetService] _ in
            try await resetService.resetAndRedownload()
        }

        // First confirmation attempt: blocked, stays pending.
        await monitor.refreshPendingDecision()
        await #expect(throws: (any Error).self) { try await monitor.confirmApply() }
        #expect(applied.hasApplied(e.id) == false)

        // The migration finishes and releases the gate.
        gate.release()

        // Confirming again (the user retries, or a fresh scan + confirm):
        // the reset now runs for real and the event is consumed.
        try await monitor.confirmApply()
        #expect(applied.hasApplied(e.id))
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }
}
