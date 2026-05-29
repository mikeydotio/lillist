import Testing
import Foundation
import CloudKit
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
        eraser: FakeCloudKitZoneEraser = FakeCloudKitZoneEraser()
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
            localStoreRowCount: rowCount
        )
        return (coordinator, recon, journal, eraser, dir)
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
        // Give the consumer a moment to drain the terminal event.
        try? await Task.sleep(nanoseconds: 50_000_000)
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
        // Mode swapped to localOnly exactly once.
        #expect(await recon.reconfigureCalls == [.localOnly])
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

    @Test("replaceICloudWithLocal: eraser called once, reconfigure precedes erase, cancel-before-destructive")
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
        // Mode swapped to iCloudSync exactly once.
        #expect(await recon.reconfigureCalls == [.iCloudSync])
        // Journal cleared (idle) on success.
        #expect(try journal.read() == .idle)
        // .preparing precedes both the swap and the erase — proving
        // notification cancellation fires before any destructive step.
        let preparingIdx = phases.firstIndex(of: .preparing)
        let reconfigIdx = phases.firstIndex(of: .reconfiguringStore)
        let eraseIdx = phases.firstIndex {
            if case .erasingICloud = $0 { return true } else { return false }
        }
        #expect(preparingIdx != nil && reconfigIdx != nil && eraseIdx != nil)
        #expect(preparingIdx! < reconfigIdx!)
        #expect(reconfigIdx! < eraseIdx!)
    }

    // MARK: - Failure-injection test

    @Test("Reconfigure failure leaves .failed journal with previousMode and rethrows")
    @MainActor
    func reconfigureFailureLeavesFailedJournal() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(startMode: .iCloudSync)
        // Arm the fake to throw on the first reconfigure call.
        await recon.failOnReconfigure(call: 1)
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
        // The fake's mode must be unchanged — the throw keeps the mode at iCloudSync.
        #expect(await recon.mode == .iCloudSync)
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
