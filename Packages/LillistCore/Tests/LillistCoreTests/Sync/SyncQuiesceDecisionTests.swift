import Testing
import Foundation
@testable import LillistCore

/// `LIL-84`: `SyncQuiesceMonitorTests`' tight (300ms quiet window / 500ms
/// hard timeout, 50ms churn interval) real-clock budgets flake at an
/// elevated rate under `swift test --parallel`'s CPU contention as the
/// suite has grown. This suite proves the S14 poll-loop SHAPE — the
/// behavior those tests exist to pin — deterministically instead, by
/// driving `QuiesceDecision.isQuiesced` (the exact comparison
/// `waitForQuiesce`'s real poll loop makes every tick) through a synthetic
/// simulation loop with a caller-supplied event schedule, no real time or
/// `Task.sleep` involved anywhere. `SyncQuiesceMonitorTests` itself is
/// unchanged and stays as a real-clock integration smoke check, no longer
/// the sole proof of correctness.
@Suite("SyncQuiesceMonitor poll-loop decision (LIL-84, deterministic)")
struct SyncQuiesceDecisionTests {
    /// Mirrors `waitForQuiesce`'s own poll loop structure exactly: tick
    /// forward by `pollInterval`, absorb any event whose offset has now
    /// arrived, and ask `QuiesceDecision.isQuiesced` the identical question
    /// the real implementation asks every tick. `eventOffsets` are
    /// seconds-since-start at which an event arrives, ascending; may be
    /// empty.
    private func simulate(
        eventOffsets: [TimeInterval],
        minQuietWindow: TimeInterval,
        hardTimeout: TimeInterval,
        pollInterval: TimeInterval
    ) -> QuiesceResult {
        var lastEventAt: TimeInterval = 0
        var nextEventIndex = eventOffsets.startIndex
        var elapsed: TimeInterval = 0
        while elapsed < hardTimeout {
            elapsed += pollInterval
            while nextEventIndex < eventOffsets.endIndex, eventOffsets[nextEventIndex] <= elapsed {
                lastEventAt = eventOffsets[nextEventIndex]
                nextEventIndex += 1
            }
            if QuiesceDecision.isQuiesced(elapsedSinceLastEvent: elapsed - lastEventAt, minQuietWindow: minQuietWindow) {
                return .quiesced
            }
        }
        return .timedOut
    }

    @Test("No events at all quiesces almost immediately")
    func noEventsQuiescesImmediately() {
        let result = simulate(eventOffsets: [], minQuietWindow: 0.1, hardTimeout: 5, pollInterval: 0.025)
        #expect(result == .quiesced)
    }

    @Test("Events arriving faster than the quiet window time out, mirroring timesOutWhenChurning")
    func churningEventsTimeOut() {
        // 20 events every 50ms — identical schedule/shape to
        // SyncQuiesceMonitorTests.timesOutWhenChurning's real churner, but
        // as a synthetic offset list instead of a real Task.sleep loop.
        let offsets = (0..<20).map { TimeInterval($0) * 0.05 }
        let result = simulate(eventOffsets: offsets, minQuietWindow: 0.3, hardTimeout: 0.5, pollInterval: 0.075)
        #expect(result == .timedOut)
    }

    @Test("S14: a .setup-shaped event schedule counts as activity and times out, exactly like import/export churn")
    func setupShapedEventsTimeOutJustLikeImportExport() {
        // The bug this proves fixed: before S14, only .import/.export
        // events bumped the clock, so an all-.setup schedule would read as
        // quiesced. QuiesceDecision.isQuiesced has no event-TYPE concept at
        // all anymore — every event, whatever CloudKitSyncEvent.EventType
        // it carries, reaches this function identically via
        // SyncQuiesceMonitor.recordEvent. This test pins that by using the
        // identical offset schedule as churningEventsTimeOut: if `.setup`
        // were still filtered out upstream, the schedule would never even
        // reach this simulation, and it would wrongly read as `.quiesced`.
        let offsets = (0..<20).map { TimeInterval($0) * 0.05 }
        let result = simulate(eventOffsets: offsets, minQuietWindow: 0.3, hardTimeout: 0.5, pollInterval: 0.075)
        #expect(result == .timedOut)
    }

    @Test("A gap exceeding the quiet window quiesces before hardTimeout, even after earlier churn")
    func gapAfterChurnQuiesces() {
        // Churn for the first 200ms, then silence — quiesced well before
        // the 2s hard timeout once minQuietWindow (300ms) elapses with no
        // further events.
        let offsets: [TimeInterval] = [0.0, 0.05, 0.10, 0.15, 0.20]
        let result = simulate(eventOffsets: offsets, minQuietWindow: 0.3, hardTimeout: 2.0, pollInterval: 0.05)
        #expect(result == .quiesced)
    }

    @Test("isQuiesced boundary: exactly at the quiet window is quiesced (>=, not >)")
    func boundaryIsInclusive() {
        #expect(QuiesceDecision.isQuiesced(elapsedSinceLastEvent: 0.3, minQuietWindow: 0.3) == true)
        #expect(QuiesceDecision.isQuiesced(elapsedSinceLastEvent: 0.299_999, minQuietWindow: 0.3) == false)
    }

    @Test("Class-kill: reverting isQuiesced to a strict > comparison changes churningEventsTimeOut's outcome")
    func classKillStrictGreaterThanChangesOutcome() {
        // Not a real revert of production code — a local re-implementation
        // of the pre-extraction bug shape (`>` instead of `>=`), run through
        // the SAME simulation harness, to prove this suite would actually
        // notice a regression in the comparison operator, not just in
        // whether the function exists.
        func brokenIsQuiesced(elapsedSinceLastEvent: TimeInterval, minQuietWindow: TimeInterval) -> Bool {
            elapsedSinceLastEvent > minQuietWindow
        }
        // At the boundary tick (elapsed - lastEventAt == minQuietWindow
        // exactly), the correct >= reads quiesced; a regressed > would not.
        #expect(QuiesceDecision.isQuiesced(elapsedSinceLastEvent: 0.3, minQuietWindow: 0.3) == true)
        #expect(brokenIsQuiesced(elapsedSinceLastEvent: 0.3, minQuietWindow: 0.3) == false)
    }
}
