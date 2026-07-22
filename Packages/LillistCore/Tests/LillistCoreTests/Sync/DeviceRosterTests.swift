import Testing
import Foundation
@testable import LillistCore

@Suite("DeviceRoster")
struct DeviceRosterTests {
    @Test("register writes only this device's own key")
    func registerIsSingleWriter() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let now = Date()

        roster.register(id: "device-A", displayName: "Nephele", now: now)

        #expect(kv.data(forKey: "device.device-A") != nil)
        #expect(kv.keys(withPrefix: "device.").count == 1)
    }

    @Test("re-registering the same device overwrites only its own entry")
    func reregisterOverwritesOwnEntry() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let first = Date(timeIntervalSince1970: 1000)
        let second = Date(timeIntervalSince1970: 2000)

        roster.register(id: "device-A", displayName: "Nephele", now: first)
        roster.register(id: "device-A", displayName: "Nephele", now: second)

        #expect(kv.keys(withPrefix: "device.").count == 1)
        let peers = roster.knownPeers(excluding: "someone-else")
        #expect(peers.count == 1)
        #expect(peers.first?.lastSeenAt == second)
    }

    @Test("knownPeers excludes self and decodes every other registered device")
    func knownPeersExcludesSelf() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let now = Date()

        roster.register(id: "device-A", displayName: "Nephele", now: now)
        roster.register(id: "device-B", displayName: "Vertumnus", now: now)
        roster.register(id: "device-C", displayName: "Ceres", now: now)

        let peers = roster.knownPeers(excluding: "device-A")

        #expect(peers.count == 2)
        #expect(Set(peers.map(\.id)) == ["device-B", "device-C"])
        #expect(Set(peers.map(\.displayName)) == ["Vertumnus", "Ceres"])
    }

    @Test("knownPeers is empty when this is the only registered device")
    func knownPeersEmptyWhenAlone() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)

        roster.register(id: "device-A", displayName: "Nephele")

        #expect(roster.knownPeers(excluding: "device-A").isEmpty)
    }

    @Test("knownPeers is empty before any device has registered")
    func knownPeersEmptyWhenUnregistered() {
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)

        #expect(roster.knownPeers(excluding: "device-A").isEmpty)
    }
}
