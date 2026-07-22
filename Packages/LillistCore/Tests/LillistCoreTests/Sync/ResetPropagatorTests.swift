import Testing
import Foundation
@testable import LillistCore

@Suite("ResetPropagator")
struct ResetPropagatorTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("broadcast registers this device, then sends to every other known peer")
    func broadcastRegistersAndFansOut() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        // A peer that registered before this device ever broadcast anything.
        roster.register(id: "device-B", displayName: "Vertumnus", now: Self.fixedNow)
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )

        propagator.broadcast(.resetToEmpty, now: Self.fixedNow)

        // Registered itself...
        #expect(roster.knownPeers(excluding: "device-B").contains { $0.id == "device-A" })
        // ...and signalled the known peer.
        let pending = inbox.pendingEvents(for: "device-B")
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .resetToEmpty)
        #expect(pending.first?.senderDeviceID == "device-A")
        #expect(pending.first?.senderDisplayName == "Nephele")
    }

    @Test("broadcast with no known peers still registers this device but sends nothing")
    func broadcastAloneRegistersOnly() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )

        propagator.broadcast(.resetAndReseed, now: Self.fixedNow)

        #expect(kv.data(forKey: "device.device-A") != nil)
        #expect(kv.keys(withPrefix: "inbox.").isEmpty)
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
