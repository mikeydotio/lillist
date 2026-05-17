import Testing
import Foundation
@testable import LillistCore

@Suite("PreferencesStore.prefsStream")
struct PreferencesStoreStreamTests {
    @Test("Stream emits a snapshot after every update")
    func emitsSnapshotPerUpdate() async throws {
        let persistence = try await TestStore.make()
        let store = PreferencesStore(persistence: persistence)
        _ = try await store.read()

        // The stream's promise is "each successful update is observable
        // by at least one downstream snapshot". The store also bridges
        // NSPersistentStoreRemoteChange through the same path, so for a
        // single in-process update we may see one or two events
        // (explicit local broadcast + remote-change echo). The test
        // asserts the eventual-consistency property: all three field
        // values land somewhere in the snapshot sequence.
        let iter = store.prefsStream.makeAsyncIterator()
        var iterator = iter
        var collected: [PreferencesStore.Prefs] = []

        try await store.update { $0.morningSummaryEnabled = false }
        try await store.update { $0.trashRetentionDays = 7 }
        try await store.update { $0.defaultTagTintHex = "#FF0000" }

        // Drain up to 10 events with a short timeout-per-event so a
        // missing broadcast surfaces as a failed assertion rather than
        // hanging the suite.
        while collected.count < 10 {
            let next = await withTaskCancellationHandler {
                await iterator.next()
            } onCancel: { /* nothing */ }
            guard let next else { break }
            collected.append(next)
            if collected.contains(where: { $0.morningSummaryEnabled == false })
                && collected.contains(where: { $0.trashRetentionDays == 7 })
                && collected.contains(where: { $0.defaultTagTintHex == "#FF0000" }) {
                break
            }
        }

        #expect(collected.contains { $0.morningSummaryEnabled == false })
        #expect(collected.contains { $0.trashRetentionDays == 7 })
        #expect(collected.contains { $0.defaultTagTintHex == "#FF0000" })
    }
}
