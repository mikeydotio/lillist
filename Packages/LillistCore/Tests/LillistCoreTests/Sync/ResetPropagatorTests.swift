import Testing
import Foundation
@testable import LillistCore

@Suite("ResetPropagator")
struct ResetPropagatorTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("broadcast registers this device, then sends to every other known peer, reporting reach")
    func broadcastRegistersAndFansOut() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        // A peer that registered before this device ever broadcast anything.
        roster.register(id: "device-B", displayName: "Vertumnus", now: Self.fixedNow)
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )

        let outcome = propagator.broadcast(.resetToEmpty, now: Self.fixedNow)

        #expect(outcome == .notified(peerCount: 1))
        // Registered itself...
        #expect(roster.knownPeers(excluding: "device-B").contains { $0.id == "device-A" })
        // ...and signalled the known peer.
        let pending = inbox.pendingEvents(for: "device-B")
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .resetToEmpty)
        #expect(pending.first?.senderDeviceID == "device-A")
        #expect(pending.first?.senderDisplayName == "Nephele")
    }

    @Test("S20: broadcast with no known peers still registers this device, sends nothing, and reports rosterEmpty rather than silent success")
    func broadcastAloneReportsRosterEmpty() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )

        let outcome = propagator.broadcast(.resetAndReseed, now: Self.fixedNow)

        #expect(outcome == .rosterEmpty)
        #expect(kv.data(forKey: "device.device-A") != nil)
        #expect(kv.keys(withPrefix: "inbox.").isEmpty)
    }

    @Test("S20: broadcasting to multiple peers reports the exact peer count")
    func broadcastReportsExactPeerCount() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus", now: Self.fixedNow)
        roster.register(id: "device-C", displayName: "Ceres", now: Self.fixedNow)
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )

        let outcome = propagator.broadcast(.resetToEmpty, now: Self.fixedNow)

        #expect(outcome == .notified(peerCount: 2))
    }

    @Test("every peer signalled by one broadcast shares the same event id")
    func broadcastSharesOneEventIDAcrossPeers() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus", now: Self.fixedNow)
        roster.register(id: "device-C", displayName: "Ceres", now: Self.fixedNow)
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )

        propagator.broadcast(.resetToEmpty, now: Self.fixedNow)

        let idB = inbox.pendingEvents(for: "device-B").first?.id
        let idC = inbox.pendingEvents(for: "device-C").first?.id
        #expect(idB != nil)
        #expect(idB == idC)
    }
}
