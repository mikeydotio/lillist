import Testing
import Foundation
@testable import LillistCore

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

    /// Records every event handed to `apply`, thread-safe for the tests'
    /// concurrent-tick scenario.
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

    @Test("a pending event is applied, marked applied locally, then acknowledged")
    func appliesRecordsAndAcknowledges() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = ResetControlEvent(
            kind: .resetToEmpty, senderDeviceID: "device-A",
            senderDisplayName: "Nephele", requestedAt: Self.fixedNow
        )
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { event in try await recorder.record(event.id) }

        await monitor.checkAndApply()

        #expect(await recorder.appliedIDs == [e.id])
        #expect(applied.hasApplied(e.id))
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("multiple pending events are all applied in one pass")
    func appliesEveryPendingEvent() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let first = ResetControlEvent(
            kind: .resetToEmpty, senderDeviceID: "device-A",
            senderDisplayName: "Nephele", requestedAt: Self.fixedNow
        )
        let second = ResetControlEvent(
            kind: .resetAndReseed, senderDeviceID: "device-C",
            senderDisplayName: "Ceres", requestedAt: Self.fixedNow
        )
        inbox.send(first, to: [peer("device-B")])
        inbox.send(second, to: [peer("device-B")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { event in try await recorder.record(event.id) }

        await monitor.checkAndApply()

        #expect(Set(await recorder.appliedIDs) == [first.id, second.id])
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("CRASH RECOVERY: an event already recorded as applied (crash between apply and ack) is never re-applied — only the stale ack is retried")
    func crashBetweenApplyAndAckDoesNotReapply() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = ResetControlEvent(
            kind: .resetToEmpty, senderDeviceID: "device-A",
            senderDisplayName: "Nephele", requestedAt: Self.fixedNow
        )
        inbox.send(e, to: [peer("device-B")])
        // Simulate: a previous run already applied this event and recorded
        // it locally, but crashed before the KVS acknowledge landed — the
        // entry is still sitting in the inbox.
        applied.markApplied(e.id)
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { event in try await recorder.record(event.id) }

        await monitor.checkAndApply()

        // Never re-applied...
        #expect(await recorder.appliedIDs.isEmpty)
        // ...but the stale entry is still cleaned up.
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("a failed apply leaves the event pending for the next tick, not acknowledged")
    func failedApplyLeavesEventPending() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = ResetControlEvent(
            kind: .resetToEmpty, senderDeviceID: "device-A",
            senderDisplayName: "Nephele", requestedAt: Self.fixedNow
        )
        inbox.send(e, to: [peer("device-B")])
        let recorder = ApplyRecorder()
        await recorder.setShouldThrow(true)

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { event in try await recorder.record(event.id) }

        await monitor.checkAndApply()

        #expect(applied.hasApplied(e.id) == false)
        #expect(inbox.pendingEvents(for: "device-B") == [e])
    }

    @Test("events addressed to a different device are never applied or touched")
    func ignoresEventsAddressedElsewhere() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let e = ResetControlEvent(
            kind: .resetToEmpty, senderDeviceID: "device-A",
            senderDisplayName: "Nephele", requestedAt: Self.fixedNow
        )
        inbox.send(e, to: [peer("device-C")])
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { event in try await recorder.record(event.id) }

        await monitor.checkAndApply()

        #expect(await recorder.appliedIDs.isEmpty)
        #expect(inbox.pendingEvents(for: "device-C") == [e])
    }

    @Test("no pending events is a harmless no-op")
    func noPendingEventsIsNoop() async {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let applied = AppliedEventStore(defaults: freshDefaults())
        let recorder = ApplyRecorder()

        let monitor = ResetSignalMonitor(
            inbox: inbox, applied: applied, deviceID: "device-B"
        ) { event in try await recorder.record(event.id) }

        await monitor.checkAndApply()

        #expect(await recorder.appliedIDs.isEmpty)
    }
}
