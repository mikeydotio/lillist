import Testing
import Foundation
import CloudKit
import CoreData
@testable import LillistCore

@Suite("MigrationCoordinator runner (executing, no live store)", .serialized)
struct MigrationRunnerExecutingTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigRunner-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeCoordinator(
        startMode: SyncMode,
        rowCount: @escaping @Sendable () async -> Int = { 1 },
        journal: InMemoryMigrationJournalStore = InMemoryMigrationJournalStore(),
        eraser: FakeCloudKitZoneEraser = FakeCloudKitZoneEraser(),
        syncStatusReset: (@Sendable () async -> Void)? = nil
    ) -> (MigrationCoordinator, FakePersistenceReconfigurer, InMemoryMigrationJournalStore, FakeCloudKitZoneEraser, URL) {
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: startMode)
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: rowCount,
            syncStatusReset: syncStatusReset
        )
        return (coordinator, recon, journal, eraser, dir)
    }

    /// Test-only call counter for `syncStatusReset` (S21) — an actor so
    /// the closure can safely bump it from the coordinator's `@MainActor`
    /// isolation.
    private actor CallCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    @Test("test_S21_successfulMigrationResetsSyncStallState")
    @MainActor
    func successfulMigrationResetsSyncStallState() async throws {
        let counter = CallCounter()
        let (coordinator, _, _, _, dir) = makeCoordinator(
            startMode: .iCloudSync,
            syncStatusReset: { await counter.bump() }
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)

        #expect(await counter.count == 1)
    }

    @Test("test_S21_failedMigrationDoesNotResetSyncStallState")
    @MainActor
    func failedMigrationDoesNotResetSyncStallState() async throws {
        let counter = CallCounter()
        let (coordinator, _, _, _, dir) = makeCoordinator(
            startMode: .localOnly, rowCount: { 0 },
            syncStatusReset: { await counter.bump() }
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }

        #expect(await counter.count == 0)
    }

    @Test("replaceICloudWithLocal on an empty local store throws before erasing")
    @MainActor
    func emptyStorePreconditionBlocksErase() async throws {
        let (coordinator, _, journal, eraser, dir) = makeCoordinator(startMode: .localOnly, rowCount: { 0 })
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)
        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // The eraser must NOT have been called — we bailed before the
        // irreversible step.
        #expect(await eraser.callCount == 0)
        // Journal is left .failed for the recovery sheet.
        #expect(try journal.read().state == .failed)
    }

    // MARK: - Phase-stream helpers

    /// Collects emitted phases from a coordinator's `progressStream`
    /// until the stream sees `.completed` or `.failed`. Runs `body`
    /// concurrently and returns the full ordered phase list after the
    /// terminal event is received.
    ///
    /// The phase-stream side-channel is the simplest correct way to
    /// assert cancel-before-destructive ordering (YAGNI): `.preparing`
    /// is always the first emission, and all destructive phases
    /// (`.reconfiguringStore`, `.erasingICloud`) follow — so asserting
    /// index ordering in the collected array proves the contract without
    /// needing a recording `NotificationScheduler` fake.
    @MainActor
    private func collectPhases(
        from coordinator: MigrationCoordinator,
        whileRunning body: @escaping @MainActor () async throws -> Void
    ) async rethrows -> [MigrationPhase] {
        let stream = coordinator.progressStream
        let collector = PhaseCollector()
        let consumer = Task {
            for await phase in stream {
                await collector.append(phase)
                if case .completed = phase { break }
                if case .failed = phase { break }
            }
        }
        defer { consumer.cancel() }
        try await body()
        // Deterministically wait for the consumer to drain the terminal
        // (.completed/.failed) event and exit its loop, instead of racing a
        // fixed sleep. Both migration success paths always emit a terminal
        // phase, so this cannot hang; if `body()` threw we never reach here
        // and the defer cancels the consumer. (The prior 50ms sleep was a
        // flaky race that intermittently dropped the terminal phase under
        // full-suite scheduling pressure.)
        await consumer.value
        return await collector.values
    }

    // MARK: - Phase-order + journal-transition tests

    @Test("disableNow: phases ordered, journal cleared, eraser NOT called")
    @MainActor
    func disableNowExecutes() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(startMode: .iCloudSync)
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        let phases = try await collectPhases(from: coordinator) {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        }

        // Eraser must not run on a disable (no CloudKit zone erasure).
        #expect(await eraser.callCount == 0)
        // S7: the trailing swap now runs through tearDown+attachStore
        // (closed-store quarantine copy), not the old reconfigure(to:)
        // path.
        #expect(await recon.resetSteps == ["tearDown"])
        #expect(await recon.attachCalls == [.localOnly])
        #expect(await recon.reconfigureCalls == [])
        // Journal cleared (idle) on success.
        #expect(try journal.read() == .idle)
        // .preparing must precede the structural swap — this proves
        // notification cancellation happens before any destructive step
        // (cancelAllPending is called inside .preparing; the scheduler
        // is nil here, so the phase ordering is the observable proof).
        let preparingIdx = phases.firstIndex(of: .preparing)
        let reconfigIdx = phases.firstIndex(of: .reconfiguringStore)
        #expect(preparingIdx != nil && reconfigIdx != nil)
        #expect(preparingIdx! < reconfigIdx!)
        // Terminal phase is .completed.
        #expect(phases.last == .completed)
    }

    @Test("replaceICloudWithLocal: eraser called once, erase precedes reconfigure, cancel-before-destructive (S6)")
    @MainActor
    func replaceICloudWithLocalExecutes() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(
            startMode: .localOnly,
            rowCount: { 5 }
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        // NOTE: targetMode == .iCloudSync triggers quiesceMonitor.waitForQuiesce
        // (minQuietWindow: 5s) — this test intentionally takes ~5s to complete.
        let phases = try await collectPhases(from: coordinator) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }

        // Eraser is called exactly once (the CloudKit zone erasure step).
        #expect(await eraser.callCount == 1)
        // S7: the trailing swap now runs through tearDown+attachStore.
        #expect(await recon.resetSteps == ["tearDown"])
        #expect(await recon.attachCalls == [.iCloudSync])
        #expect(await recon.reconfigureCalls == [])
        // Journal cleared (idle) on success.
        #expect(try journal.read() == .idle)
        // .preparing precedes both the erase and the swap — proving
        // notification cancellation fires before any destructive step.
        // S6: the erase must now precede reconfigure — attaching
        // mirroring to a store that hasn't been erased yet is the exact
        // bug this finding reports (remote data merging back in, or
        // CloudKit's export bookkeeping believing rows were already
        // uploaded before the erase that was supposed to predate them).
        let preparingIdx = phases.firstIndex(of: .preparing)
        let reconfigIdx = phases.firstIndex(of: .reconfiguringStore)
        let eraseIdx = phases.firstIndex {
            if case .erasingICloud = $0 { return true } else { return false }
        }
        #expect(preparingIdx != nil && reconfigIdx != nil && eraseIdx != nil)
        #expect(preparingIdx! < eraseIdx!)
        #expect(eraseIdx! < reconfigIdx!)
    }

    // MARK: - Failure-injection test

    @Test("attachStore failure leaves .failed journal with previousMode, reattaches, and rethrows (S7)")
    @MainActor
    func reconfigureFailureLeavesFailedJournal() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(startMode: .iCloudSync)
        // S7: disableNow's trailing swap now runs through attachStore(at:),
        // not reconfigure(to:) — arm the failure on the NEW mechanism.
        await recon.failOnAttachStore(call: 1)
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        await #expect(throws: LillistError.self) {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        }

        let j = try journal.read()
        // Journal must be left in .failed with the pre-migration mode
        // recorded so recovery knows what to revert to.
        #expect(j.state == .failed)
        #expect(j.previousMode == .iCloudSync)
        #expect(j.failureReason?.isEmpty == false)
        // Eraser never ran (disable does not erase; also we failed before it).
        #expect(await eraser.callCount == 0)
        // tearDown ran, attachStore failed, and the catch's now-
        // unconditional best-effort reattach ran too.
        #expect(await recon.resetSteps == ["tearDown", "reattach"])
        // The fake's mode must be unchanged — the throw keeps the mode at iCloudSync.
        #expect(await recon.mode == .iCloudSync)
    }

    // MARK: - S1: replaceLocalWithICloud actually wipes local data

    @Test("replaceLocalWithICloud: tears down, wipes, THEN reconfigures — local rows do NOT survive (S1 class-kill)")
    @MainActor
    func replaceLocalWithICloudWipesLocalData() async throws {
        // RealWipingReconfigurer (not the ordering-only FakePersistenceReconfigurer)
        // so this test can prove actual data loss, not just call ordering —
        // a fake that never truly clears the store would satisfy a naive
        // "reconfigure happened" assertion regardless of whether S1's bug
        // is present.
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        _ = try await taskStore.create(title: "must not survive the wipe")

        let dir = tempDir()
        let host = RealWipingReconfigurer(persistence: persistence, initialMode: .localOnly)
        let journal = InMemoryMigrationJournalStore()
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)
        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: { 1 },
            quiesceMinQuietWindow: 0.05,
            quiesceHardTimeout: 2
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")

        try await coordinator.beginEnable(direction: .replaceLocal, storeURL: storeURL)

        // Ordering: tear down -> rebuild -> THEN reconfigure to the target.
        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await host.reconfigureCalls == [.iCloudSync])
        #expect(await modeStore.currentMode() == .iCloudSync)
        #expect(try journal.read() == .idle)

        // The class-kill: the row created before the migration must be
        // GONE — the store was genuinely wiped, not merely reconfigured
        // in place (which would let the row merge into iCloud instead of
        // being replaced by it).
        let remaining = try await persistence.container.viewContext.perform {
            try persistence.container.viewContext.count(for: NSFetchRequest<LillistTask>(entityName: "LillistTask"))
        }
        #expect(remaining == 0)
    }

    @Test("replaceLocalWithICloud: a rebuildEmptyStore failure best-effort reattaches before failing (S12)")
    @MainActor
    func replaceLocalWithICloudReattachesOnRebuildFailure() async throws {
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: .localOnly)
        await recon.failOnRebuild()
        let journal = InMemoryMigrationJournalStore()
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: { 1 }
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceLocal, storeURL: storeURL)
        }

        // tearDown ran, rebuild failed, and the catch's best-effort
        // reattach ran too — the coordinator must never be left
        // store-less on this failure path (S12). reconfigure never ran
        // (rebuild failed before it), so mode is unchanged.
        #expect(await recon.resetSteps == ["tearDown", "rebuild", "reattach"])
        #expect(await recon.reconfigureCalls == [])
        #expect(await modeStore.currentMode() == .localOnly)
        let j = try journal.read()
        #expect(j.state == .failed)
    }

    @Test("test_S3_replaceLocalWithICloudRefusesOnAccountChanged")
    @MainActor
    func replaceLocalWithICloudRefusesOnAccountChanged() async throws {
        // Data-sync-hardening S3: unlike .replaceICloudWithLocal (which
        // already had this preflight), .replaceLocalWithICloud had NO
        // accountStateProvider check at all — a user could flip the sync
        // toggle on in Settings while an account mismatch was still
        // unresolved and wipe their local data to download the WRONG
        // account's copy. Placed at the same relative position
        // .replaceICloudWithLocal already uses: AFTER the recovery-anchor
        // backup (tearDownStore), BEFORE the truly irreversible step
        // (here, rebuildEmptyStore's local wipe) — so the reentrant
        // catch's unconditional reattach still has a backup to fall back
        // on if this check fires.
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: .localOnly)
        let journal = InMemoryMigrationJournalStore()
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)
        let provider: AccountStateProviding = { .accountChanged }
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: { 1 },
            accountStateProvider: provider
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceLocal, storeURL: storeURL)
        }

        // The recovery-anchor backup ran (tearDown), the check fired
        // before the irreversible local wipe (no "rebuild" step), and the
        // outer catch's unconditional reattach ran — the coordinator is
        // never left store-less.
        #expect(await recon.resetSteps == ["tearDown", "reattach"])
        #expect(await recon.reconfigureCalls == [])
        #expect(await modeStore.currentMode() == .localOnly)
        #expect(try journal.read().state == .failed)
    }

    // MARK: - S5/S14: syncFirstThenDisable quiesces BEFORE detaching

    @Test("syncFirstThenDisable: quiesces THEN detaches, in that order (S5 happy path)")
    @MainActor
    func syncFirstThenDisableQuiescesBeforeDetaching() async throws {
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let journal = InMemoryMigrationJournalStore()
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.iCloudSync)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            quiesceMinQuietWindow: 0.05,
            quiesceHardTimeout: 2
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        let phases = try await collectPhases(from: coordinator) {
            try await coordinator.beginDisable(strategy: .syncFirst, storeURL: storeURL)
        }

        // S7: the trailing swap now runs through tearDown+attachStore.
        #expect(await recon.resetSteps == ["tearDown"])
        #expect(await recon.attachCalls == [.localOnly])
        #expect(await recon.reconfigureCalls == [])
        #expect(await modeStore.currentMode() == .localOnly)
        #expect(try journal.read() == .idle)
        let uploadIdx = phases.firstIndex { if case .uploading = $0 { return true } else { return false } }
        let reconfigIdx = phases.firstIndex(of: .reconfiguringStore)
        #expect(uploadIdx != nil && reconfigIdx != nil)
        // The final-sync wait must precede the detach — waiting AFTER
        // reconfigure(to: .localOnly) is pointless (no CloudKit container
        // remains to export through) and is exactly the bug S5 reports.
        #expect(uploadIdx! < reconfigIdx!)
    }

    @Test("syncFirstThenDisable: a quiesce timeout fails the step BEFORE detaching, never strands mode (S5/S14)")
    @MainActor
    func syncFirstThenDisableFailsClosedOnQuiesceTimeout() async throws {
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let journal = InMemoryMigrationJournalStore()
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.iCloudSync)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            // No events ever fire on this bridge, and hardTimeout sits
            // below minQuietWindow, so the wait can only ever time out —
            // that's the failure path this test proves.
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            quiesceMinQuietWindow: 1.0,
            quiesceHardTimeout: 0.05
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        await #expect(throws: LillistError.self) {
            try await coordinator.beginDisable(strategy: .syncFirst, storeURL: storeURL)
        }

        // The whole point of "sync first": a timeout must fail the step
        // BEFORE detaching mirroring, so unsynced edits are never
        // silently stranded (S5). Neither the old (reconfigure) nor the
        // new (tearDown+attachStore, S7) swap mechanism must ever have
        // run — the timeout throws before step 4's switch even starts.
        // The catch block's now-unconditional best-effort reattach DOES
        // still run (a harmless no-op here, since nothing was ever
        // detached) — that's the one "reattach" entry `resetSteps` picks
        // up.
        #expect(await recon.reconfigureCalls == [])
        #expect(await recon.resetSteps == ["reattach"])
        #expect(await recon.attachCalls == [])
        #expect(await recon.mode == .iCloudSync)
        #expect(await modeStore.currentMode() == .iCloudSync)
        #expect(try journal.read().state == .failed)
    }

    // MARK: - S7: quarantine anchor comes from the closed-store mechanism

    @Test("disableNow's quarantine anchor is captured via tearDownStore, not a direct live-store copy (S7)")
    @MainActor
    func disableNowQuarantinesViaTearDownStore() async throws {
        let (coordinator, recon, journal, _, dir) = makeCoordinator(startMode: .iCloudSync)
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("pre-disable-content".utf8).write(to: storeURL)
        // Point the fake at the real file so tearDownStore's quarantine
        // copy is genuine (see FakePersistenceReconfigurer.storeURL) —
        // this proves the capture happens via the SAME primitive
        // .replaceLocalWithICloud already used, not a direct
        // MigrationCoordinator -> quarantine call bypassing the host.
        await recon.setStoreURL(storeURL)

        try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)

        #expect(await recon.resetSteps == ["tearDown"])
        let quarantine = QuarantineManager(rootDirectory: dir)
        let backup = try quarantine.latestQuarantinedStore(filename: "Lillist.sqlite")
        #expect(backup != nil)
        #expect(try String(contentsOf: backup!, encoding: .utf8) == "pre-disable-content")
        #expect(try journal.read() == .idle)
    }

    @Test("replaceICloudWithLocal's quarantine anchor is captured via tearDownStore before the erase (S7)")
    @MainActor
    func replaceICloudWithLocalQuarantinesViaTearDownStore() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(
            startMode: .localOnly, rowCount: { 5 }
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("pre-erase-content".utf8).write(to: storeURL)
        await recon.setStoreURL(storeURL)

        try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)

        #expect(await recon.resetSteps == ["tearDown"])
        #expect(await eraser.callCount == 1)
        let quarantine = QuarantineManager(rootDirectory: dir)
        let backup = try quarantine.latestQuarantinedStore(filename: "Lillist.sqlite")
        #expect(backup != nil)
        #expect(try String(contentsOf: backup!, encoding: .utf8) == "pre-erase-content")
        #expect(try journal.read() == .idle)
    }

    // MARK: - S14: a POST-destructive quiesce timeout does not fail the migration

    @Test("replaceLocalWithICloud: a post-completion quiesce timeout still COMPLETES the migration (S14 — nothing left to revert)")
    @MainActor
    func postDestructiveQuiesceTimeoutStillCompletes() async throws {
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: .localOnly)
        let journal = InMemoryMigrationJournalStore()
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: { 1 },
            quiesceMinQuietWindow: 1.0,
            quiesceHardTimeout: 0.05
        )
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        // The wait times out (hardTimeout < minQuietWindow, no events
        // ever fire). The destructive work (tear down + rebuild +
        // reconfigure) already succeeded by this point, so the migration
        // must still COMPLETE rather than fail — there is nothing left
        // to revert, and failing here would strand the user on a
        // half-migrated store for no benefit (matches
        // `QuiesceResult.timedOut`'s own documented "proceeds anyway"
        // contract).
        try await coordinator.beginEnable(direction: .replaceLocal, storeURL: storeURL)

        #expect(await recon.reconfigureCalls == [.iCloudSync])
        #expect(await modeStore.currentMode() == .iCloudSync)
        #expect(try journal.read() == .idle)
    }
}

// MARK: - Thread-safe phase collector

/// Thread-safe ordered sink for emitted `MigrationPhase` values.
/// Actor isolation ensures appends from the consumer `Task` are
/// data-race-free.
actor PhaseCollector {
    private(set) var values: [MigrationPhase] = []

    func append(_ phase: MigrationPhase) {
        values.append(phase)
    }
}
