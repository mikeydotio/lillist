import Testing
import Foundation
@testable import LillistCore

@Suite("SyncStatusMonitor")
struct SyncStatusMonitorTests {
    @Test("Initial status is idle")
    func initial() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        #expect(await monitor.currentStatus == .idle)
    }

    @Test("Setup-started event sets inProgress to true")
    func setupStarted() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        // Use the monitor's statusStream as the synchronization primitive.
        // `iterator.next()` on the post-record yield is a real happens-before:
        // it only returns after `apply` has updated `currentStatus` and
        // yielded to subscribers. No yield-polling needed.
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay (state .idle)

        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let next = await iterator.next()

        #expect(next?.inProgress == true)
        #expect(next?.error == nil)
        // currentStatus is also consistent now that we waited for apply.
        let status = await monitor.currentStatus
        #expect(status.inProgress == true)
        #expect(status.error == nil)
    }

    @Test("Successful import completion clears inProgress and sets lastSyncedAt")
    func importCompletes() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let end = Date(timeIntervalSince1970: 2_000_000)
        await bridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
        _ = await iterator.next() // state after start

        await bridge.recordEvent(.init(type: .import, started: false, endedAt: end, error: nil))
        let final = await iterator.next() // state after end

        #expect(final?.inProgress == false)
        #expect(final?.lastSyncedAt == end)
        #expect(final?.error == nil)
    }

    @Test("Failed export records the error and clears inProgress")
    func exportFails() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let err = LillistError.syncFailure(underlying: "network down")
        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        _ = await iterator.next() // state after start

        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: err))
        let final = await iterator.next() // state after failure

        #expect(final?.inProgress == false)
        #expect(final?.error == err)
    }

    @Test("A recoverable failed export does NOT latch a red error")
    func recoverableExportDoesNotLatch() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        // A prior successful import establishes a lastSyncedAt.
        let synced = Date(timeIntervalSince1970: 3_000_000)
        await bridge.recordEvent(.init(type: .import, started: false, endedAt: synced, error: nil))
        _ = await iterator.next()

        // A transient export partialFailure (recoverable) must NOT set a red
        // error and must preserve the prior lastSyncedAt — the fix for the
        // permanent "CKErrorDomain error 2" badge from a one-off conflict.
        let err = LillistError.syncFailure(underlying: "1 record failed (serverRecordChanged: 1)")
        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: err, recoverable: true))
        let final = await iterator.next()

        #expect(final?.inProgress == false)
        #expect(final?.error == nil, "a transient failure must not latch a red error")
        #expect(final?.lastSyncedAt == synced, "prior lastSyncedAt should be preserved")
    }

    @Test("Status stream yields updates")
    func statusStream() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let next = await iterator.next()
        #expect(next?.inProgress == true)
    }

    // MARK: - Issue #66: persistent export-stall detection

    /// Records N recoverable export-failure events (start+end pairs) and
    /// returns the status after the last one.
    private func recordRecoverableExportFailures(
        _ count: Int,
        bridge: CloudKitEventBridge,
        iterator: inout AsyncStream<SyncStatus>.AsyncIterator
    ) async -> SyncStatus? {
        var final: SyncStatus?
        for _ in 0..<count {
            await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
            _ = await iterator.next()
            await bridge.recordEvent(.init(
                type: .export, started: false, endedAt: Date(),
                error: .syncFailure(underlying: "1 record failed"), recoverable: true
            ))
            final = await iterator.next()
        }
        return final
    }

    @Test("Two consecutive recoverable export failures stay calm (below default threshold 3)")
    func belowThresholdStaysCalm() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let final = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(final?.error == nil, "a one-off or two-in-a-row blip must stay calm")
    }

    @Test("The Nth consecutive recoverable export failure escalates to a stalled error")
    func nthFailureEscalates() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let final = await recordRecoverableExportFailures(3, bridge: bridge, iterator: &iterator)
        #expect(final?.error == .syncStalled(consecutiveFailures: 3))
        #expect(await monitor.consecutiveExportFailures == 3)
    }

    @Test("A successful export resets the consecutive-failure streak")
    func successResetsStreak() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        _ = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(await monitor.consecutiveExportFailures == 2)

        // A clean export success in between resets the streak.
        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: nil))
        _ = await iterator.next()
        #expect(await monitor.consecutiveExportFailures == 0)

        // Two more failures should NOT reach the threshold — the streak restarted.
        let final = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(final?.error == nil, "streak restarted after the success, so 2 more stays calm")
    }

    @Test("A structural export failure resets the streak and surfaces immediately")
    func structuralFailureResetsStreak() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        _ = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)

        let structural = LillistError.quotaExceeded(resource: "iCloud")
        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: structural, recoverable: false))
        let afterStructural = await iterator.next()
        #expect(afterStructural?.error == structural, "structural failures still surface immediately")
        #expect(await monitor.consecutiveExportFailures == 0, "a structural failure resets the recoverable streak")
    }

    @Test("Import events never contribute to the export stall counter")
    func importEventsDoNotCountTowardExportStall() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        // Two export failures (below threshold)...
        _ = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)

        // ...interleaved with a recoverable IMPORT failure, which must not
        // push the export streak toward the threshold.
        await bridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
        _ = await iterator.next()
        await bridge.recordEvent(.init(
            type: .import, started: false, endedAt: Date(),
            error: .syncFailure(underlying: "import blip"), recoverable: true
        ))
        _ = await iterator.next()
        #expect(await monitor.consecutiveExportFailures == 2, "import events must not touch the export counter")

        // One more export failure now reaches the threshold (3rd export failure overall).
        let final = await recordRecoverableExportFailures(1, bridge: bridge, iterator: &iterator)
        #expect(final?.error == .syncStalled(consecutiveFailures: 3))
    }

    @Test("A custom stallThreshold is honored")
    func customStallThreshold() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge, stallThreshold: 1)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let final = await recordRecoverableExportFailures(1, bridge: bridge, iterator: &iterator)
        #expect(final?.error == .syncStalled(consecutiveFailures: 1))
    }

    // MARK: - Issue #66: export-health capture for diagnostics

    @Test("A failed export records the raw CKError domain/code")
    func exportFailureRecordsRawError() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        _ = await iterator.next()
        await bridge.recordEvent(.init(
            type: .export, started: false, endedAt: Date(),
            error: .syncFailure(underlying: "1 record failed"), recoverable: true,
            rawErrorDomain: "CKErrorDomain", rawErrorCode: 2
        ))
        _ = await iterator.next()

        let health = await monitor.exportHealth
        #expect(health.consecutiveFailures == 1)
        #expect(health.lastErrorDomain == "CKErrorDomain")
        #expect(health.lastErrorCode == 2)
    }

    @Test("The last export error persists across a later success (forensic history)")
    func lastExportErrorPersistsAcrossSuccess() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        _ = await iterator.next()
        await bridge.recordEvent(.init(
            type: .export, started: false, endedAt: Date(),
            error: .syncFailure(underlying: "1 record failed"), recoverable: true,
            rawErrorDomain: "CKErrorDomain", rawErrorCode: 2
        ))
        _ = await iterator.next()

        // A subsequent successful export resets the *streak* but the last
        // error's domain/code remain as forensic history — a diagnostics
        // reader can tell "hit CKErrorDomain/2 at some point, but 0
        // consecutive failures now" apart from "never hit anything."
        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: nil))
        _ = await iterator.next()

        let health = await monitor.exportHealth
        #expect(health.consecutiveFailures == 0)
        #expect(health.lastErrorDomain == "CKErrorDomain")
        #expect(health.lastErrorCode == 2)
    }

    @Test("No export failure yet leaves exportHealth at its zero value")
    func exportHealthDefaultsToZero() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        let health = await monitor.exportHealth
        #expect(health == SyncStatusMonitor.ExportHealth(consecutiveFailures: 0, lastErrorDomain: nil, lastErrorCode: nil))
    }

    // MARK: - S21: import-axis stall escalation (mirrors the export axis)

    private func recordRecoverableImportFailures(
        _ count: Int,
        bridge: CloudKitEventBridge,
        iterator: inout AsyncStream<SyncStatus>.AsyncIterator
    ) async -> SyncStatus? {
        var final: SyncStatus?
        for _ in 0..<count {
            await bridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
            _ = await iterator.next()
            await bridge.recordEvent(.init(
                type: .import, started: false, endedAt: Date(),
                error: .syncFailure(underlying: "1 record failed"), recoverable: true
            ))
            final = await iterator.next()
        }
        return final
    }

    @Test("test_S21_importStallEscalatesAtThreshold")
    func importStallEscalatesAtThreshold() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let final = await recordRecoverableImportFailures(3, bridge: bridge, iterator: &iterator)
        #expect(final?.error == .syncStalled(consecutiveFailures: 3))
        #expect(await monitor.consecutiveImportFailures == 3)
    }

    @Test("test_S21_importStreakResetsOnSuccess")
    func importStreakResetsOnSuccess() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        _ = await recordRecoverableImportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(await monitor.consecutiveImportFailures == 2)

        await bridge.recordEvent(.init(type: .import, started: false, endedAt: Date(), error: nil))
        _ = await iterator.next()
        #expect(await monitor.consecutiveImportFailures == 0)

        let final = await recordRecoverableImportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(final?.error == nil, "streak restarted after the success, so 2 more stays calm")
    }

    @Test("test_S21_structuralImportFailureResetsStreak")
    func structuralImportFailureResetsStreak() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        _ = await recordRecoverableImportFailures(2, bridge: bridge, iterator: &iterator)

        let structural = LillistError.quotaExceeded(resource: "iCloud")
        await bridge.recordEvent(.init(type: .import, started: false, endedAt: Date(), error: structural, recoverable: false))
        let afterStructural = await iterator.next()
        #expect(afterStructural?.error == structural)
        #expect(await monitor.consecutiveImportFailures == 0)
    }

    @Test("test_S21_exportAndImportStreaksAreIndependent")
    func exportAndImportStreaksAreIndependent() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        // Two export failures (below threshold), two import failures
        // (below threshold) interleaved — neither axis should push the
        // other toward its own threshold.
        _ = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)
        _ = await recordRecoverableImportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(await monitor.consecutiveExportFailures == 2)
        #expect(await monitor.consecutiveImportFailures == 2)

        // One more of each reaches each axis's own threshold independently.
        let exportFinal = await recordRecoverableExportFailures(1, bridge: bridge, iterator: &iterator)
        #expect(exportFinal?.error == .syncStalled(consecutiveFailures: 3))
        let importFinal = await recordRecoverableImportFailures(1, bridge: bridge, iterator: &iterator)
        #expect(importFinal?.error == .syncStalled(consecutiveFailures: 3))
    }

    @Test("test_S21_resetStallStateClearsBothAxesAndForensics")
    func resetStallStateClearsBothAxesAndForensics() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        _ = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)
        _ = await recordRecoverableImportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(await monitor.consecutiveExportFailures == 2)
        #expect(await monitor.consecutiveImportFailures == 2)

        // Record forensic-history detail explicitly (the shared helpers
        // above don't set rawErrorDomain/rawErrorCode) so the reset's
        // forensics-clearing behavior has something real to clear.
        await bridge.recordEvent(.init(
            type: .export, started: false, endedAt: Date(),
            error: .syncFailure(underlying: "1 record failed"), recoverable: true,
            rawErrorDomain: "CKErrorDomain", rawErrorCode: 2
        ))
        _ = await iterator.next()
        await bridge.recordEvent(.init(
            type: .import, started: false, endedAt: Date(),
            error: .syncFailure(underlying: "1 record failed"), recoverable: true,
            rawErrorDomain: "CKErrorDomain", rawErrorCode: 2
        ))
        _ = await iterator.next()
        #expect(await monitor.exportHealth.lastErrorDomain != nil)
        #expect(await monitor.importHealth.lastErrorDomain != nil)

        await monitor.resetStallState()

        #expect(await monitor.consecutiveExportFailures == 0)
        #expect(await monitor.consecutiveImportFailures == 0)
        #expect(await monitor.exportHealth == SyncStatusMonitor.ExportHealth(consecutiveFailures: 0, lastErrorDomain: nil, lastErrorCode: nil))
        #expect(await monitor.importHealth == SyncStatusMonitor.ImportHealth(consecutiveFailures: 0, lastErrorDomain: nil, lastErrorCode: nil))

        // A fresh streak after the reset starts from zero, not from where
        // the cleared streak left off.
        let final = await recordRecoverableExportFailures(2, bridge: bridge, iterator: &iterator)
        #expect(final?.error == nil)
    }

    @Test("No import failure yet leaves importHealth at its zero value")
    func importHealthDefaultsToZero() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        let health = await monitor.importHealth
        #expect(health == SyncStatusMonitor.ImportHealth(consecutiveFailures: 0, lastErrorDomain: nil, lastErrorCode: nil))
    }
}
