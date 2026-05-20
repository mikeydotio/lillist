import Testing
import Foundation
@testable import LillistCore

@Suite("SyncModeStore")
struct SyncModeStoreTests {
    private static func freshSuite() -> String {
        let name = "SyncModeStoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        return name
    }

    @Test("Defaults to iCloudSync when nothing is stored")
    func defaultsToICloudSync() async {
        let store = SyncModeStore(suiteName: Self.freshSuite())
        #expect(await store.currentMode() == .iCloudSync)
    }

    @Test("Round-trips through setMode + currentMode")
    func roundTrip() async {
        let store = SyncModeStore(suiteName: Self.freshSuite())
        await store.setMode(.localOnly)
        #expect(await store.currentMode() == .localOnly)
        await store.setMode(.iCloudSync)
        #expect(await store.currentMode() == .iCloudSync)
    }

    @Test("Stored value is visible to a fresh store backed by the same suite")
    func crossInstanceVisibility() async {
        let suite = Self.freshSuite()
        let a = SyncModeStore(suiteName: suite)
        await a.setMode(.localOnly)

        let b = SyncModeStore(suiteName: suite)
        #expect(await b.currentMode() == .localOnly)
    }

    @Test("modeStream emits the initial value on subscription, then each distinct change")
    func streamEmitsValues() async {
        let store = SyncModeStore(suiteName: Self.freshSuite())
        await store.setMode(.localOnly)

        var iterator = await store.modeStream.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial == .localOnly)

        await store.setMode(.iCloudSync)
        let next = await iterator.next()
        #expect(next == .iCloudSync)
    }

    @Test("Setting the same mode does not emit a duplicate event")
    func streamDeduplicatesIdenticalSets() async {
        let store = SyncModeStore(suiteName: Self.freshSuite())
        await store.setMode(.localOnly)
        var iterator = await store.modeStream.makeAsyncIterator()
        _ = await iterator.next()  // drain the initial value

        // Setting the same mode twice should not emit anything new.
        await store.setMode(.localOnly)

        // Switch + switch back; iterator should observe iCloudSync then
        // localOnly, not the duplicate localOnly write in between.
        await store.setMode(.iCloudSync)
        await store.setMode(.localOnly)

        #expect(await iterator.next() == .iCloudSync)
        #expect(await iterator.next() == .localOnly)
    }
}
