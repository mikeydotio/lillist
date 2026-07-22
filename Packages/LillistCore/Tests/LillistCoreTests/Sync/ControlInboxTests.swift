import Testing
import Foundation
@testable import LillistCore

@Suite("ControlInbox")
struct ControlInboxTests {
    /// A whole-second-aligned timestamp. `ResetControlEvent` round-trips
    /// through `ControlInbox`'s `.iso8601`-strategy JSON encoding (matching
    /// this codebase's established Codable-date convention), which drops
    /// sub-second precision — comparing against a raw `Date()` would make
    /// an unmodified round-tripped event spuriously != its pre-round-trip
    /// original.
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        kind: ResetControlEvent.Kind = .resetToEmpty,
        sender: String = "device-A",
        senderDisplayName: String = "Nephele",
        at: Date = ControlInboxTests.fixedNow
    ) -> ResetControlEvent {
        ResetControlEvent(
            kind: kind,
            senderDeviceID: sender,
            senderDisplayName: senderDisplayName,
            requestedAt: at
        )
    }

    private func peer(_ id: String, displayName: String = "Peer") -> RosterEntry {
        RosterEntry(id: id, displayName: displayName, lastSeenAt: Self.fixedNow)
    }

    @Test("send fans out one entry per peer, addressed individually")
    func sendFansOutPerPeer() {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let e = event()

        inbox.send(e, to: [peer("device-B"), peer("device-C")])

        #expect(inbox.pendingEvents(for: "device-B") == [e])
        #expect(inbox.pendingEvents(for: "device-C") == [e])
        #expect(inbox.pendingEvents(for: "device-D").isEmpty)
    }

    @Test("send to an empty peer list writes nothing")
    func sendToNoPeersIsNoop() {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)

        inbox.send(event(), to: [])

        #expect(kv.keys(withPrefix: "inbox.").isEmpty)
    }

    @Test("REGRESSION: two rapid sends from the SAME sender never collide (the single-slot-per-sender design this replaced silently dropped the first event when a second broadcast landed before it was read)")
    func rapidSuccessiveSendsFromSameSenderDoNotCollide() {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let first = event(kind: .resetToEmpty, sender: "device-A")
        let second = event(kind: .resetAndReseed, sender: "device-A")

        inbox.send(first, to: [peer("device-B")])
        inbox.send(second, to: [peer("device-B")])

        let pending = inbox.pendingEvents(for: "device-B")
        #expect(Set(pending.map(\.id)) == [first.id, second.id])
    }

    @Test("REGRESSION: two DIFFERENT senders signalling the SAME recipient never collide (a shared, recipient-owned mailbox array — the multi-writer design this replaced — is a lost-update race under KVS's last-writer-wins conflict resolution)")
    func concurrentSendersToSameRecipientDoNotCollide() {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let fromA = event(sender: "device-A", senderDisplayName: "Nephele")
        let fromC = event(sender: "device-C", senderDisplayName: "Ceres")

        inbox.send(fromA, to: [peer("device-B")])
        inbox.send(fromC, to: [peer("device-B")])

        let pending = inbox.pendingEvents(for: "device-B")
        #expect(Set(pending.map(\.id)) == [fromA.id, fromC.id])
        #expect(Set(pending.map(\.senderDeviceID)) == ["device-A", "device-C"])
    }

    @Test("acknowledge deletes only the addressed recipient's key")
    func acknowledgeDeletesOnlyAddresseeKey() {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let e = event()
        inbox.send(e, to: [peer("device-B"), peer("device-C")])

        inbox.acknowledge(eventID: e.id, recipient: "device-B")

        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
        // device-C's copy is untouched — acknowledging one recipient's
        // key can never race or interfere with another's.
        #expect(inbox.pendingEvents(for: "device-C") == [e])
    }

    @Test("acknowledging an already-gone event is a harmless no-op")
    func acknowledgeIsIdempotent() {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        let e = event()
        inbox.send(e, to: [peer("device-B")])
        inbox.acknowledge(eventID: e.id, recipient: "device-B")

        // Second ack of the same (already-deleted) event: no crash, no error.
        inbox.acknowledge(eventID: e.id, recipient: "device-B")

        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("pendingEvents for a recipient never sees events addressed to someone else")
    func pendingEventsAreRecipientScoped() {
        let kv = InMemoryKeyValueSyncStore()
        let inbox = ControlInbox(kv: kv)
        inbox.send(event(), to: [peer("device-B")])

        #expect(inbox.pendingEvents(for: "device-C").isEmpty)
    }
}
