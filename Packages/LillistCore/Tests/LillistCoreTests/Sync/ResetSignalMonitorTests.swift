import Testing
import Foundation
@testable import LillistCore

/// Data-sync-hardening `S10`: remote reset events are NEVER auto-applied —
/// `refreshPendingDecision()` (formerly the auto-applying `checkAndApply()`)
/// only ever classifies and surfaces; `confirmApply()` is the sole path
/// that ever invokes `apply`, and it is only ever called from explicit UI
/// confirmation in production.
@Suite("ResetSignalMonitor")
struct ResetSignalMonitorTests {
    /// A whole-second-aligned timestamp. `ResetControlEvent` round-trips
    /// through `ControlInbox`'s `.iso8601`-strategy JSON encoding (matching
    /// this codebase's established Codable-date convention), which drops
    /// sub-second precision — comparing against a raw `Date()` would make
    /// an unmodified round-tripped event spuriously != its pre-round-trip
    /// original.
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func freshDefaults() -> UserDefaults {
        let suiteName = "ResetSignalMonitorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func peer(_ id: String) -> RosterEntry {
        RosterEntry(id: id, displayName: id, lastSeenAt: Self.fixedNow)
    }

    /// Records every event handed to `apply`, thread-safe for concurrent
    /// scenarios.
    private actor ApplyRecorder {
        private(set) var appliedIDs: [UUID] = []
        private var shouldThrow = false

        func setShouldThrow(_ value: Bool) {
            shouldThrow = value
        }

        func record(_ id: UUID) throws {
            if shouldThrow {
                throw LillistError.storeUnavailable(reason: "fake apply failure")
            }
            appliedIDs.append(id)
        }
    }

    private func makeEvent(
        kind: ResetControlEvent.Kind = .resetToEmpty,
        sender: String = "device-A",
        senderName: String = "Nephele",
        requestedAt: Date = fixedNow
    ) -> ResetControlEvent {
        ResetControlEvent(kind: kind, senderDeviceID: sender, senderDisplayName: senderName, requestedAt: requestedAt)
    }

    // MARK: - Always-prompt: refreshPendingDecision never applies

    @Test("a pending event is surfaced as pendingDecision, never auto-applied")
    func surfacesWithoutApplying() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()

        #expect(await monitor.pendingDecision == e)
        #expect(await recorder.appliedIDs.isEmpty)
        #expect(applied.hasApplied(e.id) == false)
        #expect(inbox.pendingEvents(for: "device-B") == [e])
    }

    @Test("confirmApply applies the pending decision, marks it applied, and acknowledges it")
    func confirmApplyAppliesRecordsAndAcknowledges() async throws {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()
        try await monitor.confirmApply()

        #expect(await recorder.appliedIDs == [e.id])
        #expect(applied.hasApplied(e.id))
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
        #expect(await monitor.pendingDecision == nil)
    }

    @Test("confirming one pending event applies once and acknowledges every other currently-pending event too")
    func confirmApplySatisfiesEveryPendingEvent() async throws {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let first = makeEvent(sender: "device-A", senderName: "Nephele")
        let second = makeEvent(kind: .resetAndReseed, sender: "device-C", senderName: "Ceres")
        inbox.send(first, to: [peer("device-B")])
        inbox.send(second, to: [peer("device-B")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()
        // The oldest (first, by requestedAt tie broken by insertion order
        // here) is the anchor shown to the user.
        try await monitor.confirmApply()

        // Only ONE apply call — the second event is satisfied by the same
        // convergence, not a second call.
        #expect(await recorder.appliedIDs.count == 1)
        #expect(applied.hasApplied(first.id))
        #expect(applied.hasApplied(second.id))
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("CRASH RECOVERY: an event already recorded as applied (crash between apply and ack) is never re-applied — only the stale ack is retried")
    func crashBetweenApplyAndAckDoesNotReapply() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-B")])
        // Simulate: a previous run already applied this event and recorded
        // it locally, but crashed before the KVS acknowledge landed — the
        // entry is still sitting in the inbox.
        applied.markApplied(e.id)
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()

        // Never re-applied, never even surfaced as a decision...
        #expect(await recorder.appliedIDs.isEmpty)
        #expect(await monitor.pendingDecision == nil)
        // ...but the stale entry is still cleaned up.
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("a failed confirmApply leaves every pending event pending for the next confirmation, not acknowledged")
    func failedConfirmApplyLeavesEventsPending() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()
        await recorder.setShouldThrow(true)

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()
        await #expect(throws: LillistError.self) { try await monitor.confirmApply() }

        #expect(applied.hasApplied(e.id) == false)
        #expect(inbox.pendingEvents(for: "device-B") == [e])
        #expect(await monitor.pendingDecision == e)
    }

    @Test("confirmApply with nothing pending is a harmless no-op")
    func confirmApplyWithNothingPendingIsNoop() async throws {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        try await monitor.confirmApply()

        #expect(await recorder.appliedIDs.isEmpty)
    }

    @Test("events addressed to a different device are never surfaced or touched")
    func ignoresEventsAddressedElsewhere() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-C")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()

        #expect(await recorder.appliedIDs.isEmpty)
        #expect(await monitor.pendingDecision == nil)
        #expect(inbox.pendingEvents(for: "device-C") == [e])
    }

    @Test("no pending events is a harmless no-op")
    func noPendingEventsIsNoop() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()

        #expect(await recorder.appliedIDs.isEmpty)
        #expect(await monitor.pendingDecision == nil)
    }

    @Test("declining (never calling confirmApply) leaves the event re-surfaced on the next scan — nothing about a decline is persisted")
    func decliningLeavesEventRediscoverable() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()
        #expect(await monitor.pendingDecision == e)

        // "Not Now" — no monitor call at all. A later scan (next launch or
        // KVS notification) re-evaluates from scratch.
        await monitor.refreshPendingDecision()

        #expect(await monitor.pendingDecision == e)
        #expect(await recorder.appliedIDs.isEmpty)
    }

    // MARK: - S10: 180-day expiry (hygiene bound, not safety — apply is always confirmed either way)

    @Test("an event older than the 180-day expiry window is acknowledged and discarded, never surfaced")
    func expiredEventIsDiscarded() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let requestedAt = Self.fixedNow
        let e = makeEvent(requestedAt: requestedAt)
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()
        let past181Days = Calendar.current.date(byAdding: .day, value: 181, to: requestedAt)!

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { past181Days }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()

        #expect(await monitor.pendingDecision == nil)
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
        #expect(await recorder.appliedIDs.isEmpty)
        let notice = await monitor.discardNotice
        #expect(notice?.event == e)
        #expect(notice?.reason == .expired)
    }

    @Test("an event exactly 180 days old is discarded — the boundary is inclusive")
    func exactBoundaryIsExpired() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let requestedAt = Self.fixedNow
        let e = makeEvent(requestedAt: requestedAt)
        inbox.send(e, to: [peer("device-B")])
        let exactly180 = Calendar.current.date(byAdding: .day, value: 180, to: requestedAt)!

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { exactly180 }
        ) { _ in }

        await monitor.refreshPendingDecision()

        #expect(await monitor.pendingDecision == nil)
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("an event just under 180 days old is still surfaced as a pending decision")
    func justUnderBoundaryIsStillActionable() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let requestedAt = Self.fixedNow
        let e = makeEvent(requestedAt: requestedAt)
        inbox.send(e, to: [peer("device-B")])
        let justUnder = Calendar.current.date(byAdding: .day, value: 179, to: requestedAt)!

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { justUnder }
        ) { _ in }

        await monitor.refreshPendingDecision()

        #expect(await monitor.pendingDecision == e)
        #expect(inbox.pendingEvents(for: "device-B") == [e])
    }

    // MARK: - S10: local-only devices ack-and-discard instead of retrying forever

    @Test("a device in local-only mode acknowledges and discards a pending event, surfacing a discard notice instead of throwing forever")
    func localOnlyDeviceDiscardsWithNotice() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent(senderName: "Nephele")
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            currentSyncMode: { .localOnly },
            clock: { Self.fixedNow }
        ) { event in try await recorder.record(event.id) }

        await monitor.refreshPendingDecision()

        #expect(await monitor.pendingDecision == nil)
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
        #expect(await recorder.appliedIDs.isEmpty)
        let notice = await monitor.discardNotice
        #expect(notice?.event == e)
        #expect(notice?.reason == .notSyncing)
    }

    @Test("an iCloudSync device surfaces the same event as a live pending decision (control against the local-only case)")
    func iCloudSyncDeviceSurfacesNormally() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-B")])

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            currentSyncMode: { .iCloudSync },
            clock: { Self.fixedNow }
        ) { _ in }

        await monitor.refreshPendingDecision()

        #expect(await monitor.pendingDecision == e)
    }

    // MARK: - S22: undecodable payloads are quarantined, not silently lost forever

    @Test("an undecodable payload is quarantined to the dead-letter store and removed from the live inbox")
    func undecodablePayloadIsQuarantined() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        // Write raw garbage directly under this recipient's prefix — not a
        // valid ResetControlEvent JSON payload.
        let garbageKey = "inbox.device-B.\(UUID().uuidString)"
        kv.set(Data("not json".utf8), forKey: garbageKey)
        let deadLetters = ResetEventDeadLetterStore(defaults: freshDefaults())

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            deadLetters: deadLetters,
            clock: { Self.fixedNow }
        ) { _ in }

        await monitor.refreshPendingDecision()

        #expect(kv.data(forKey: garbageKey) == nil)
        #expect(deadLetters.recent().map(\.key) == [garbageKey])
        #expect(await monitor.pendingDecision == nil)
    }

    @Test("quarantining an undecodable payload is safe even without a configured dead-letter store")
    func undecodablePayloadWithoutDeadLetterStoreStillDiscards() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let garbageKey = "inbox.device-B.\(UUID().uuidString)"
        kv.set(Data("not json".utf8), forKey: garbageKey)

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { _ in }

        await monitor.refreshPendingDecision()

        #expect(kv.data(forKey: garbageKey) == nil)
    }

    // MARK: - Streams

    @Test("pendingDecisionStream yields the current value immediately, then every subsequent change")
    func pendingDecisionStreamYieldsCurrentThenChanges() async throws {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = makeEvent()
        inbox.send(e, to: [peer("device-B")])

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B",
            clock: { Self.fixedNow }
        ) { _ in }

        var iterator = await monitor.pendingDecisionStream.makeAsyncIterator()
        let initial = await iterator.next() ?? nil
        #expect(initial == nil)

        await monitor.refreshPendingDecision()
        let afterScan = await iterator.next() ?? nil
        #expect(afterScan == e)

        try await monitor.confirmApply()
        let afterApply = await iterator.next() ?? nil
        #expect(afterApply == nil)
    }
}
