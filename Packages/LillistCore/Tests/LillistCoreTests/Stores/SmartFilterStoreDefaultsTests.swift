import Testing
import Foundation
@testable import LillistCore

@Suite("SmartFilterStore.installDefaultsIfNeeded")
struct SmartFilterStoreDefaultsTests {
    @Test("Installs five default filters with the expected names on first run")
    func firstRunInstallsAll() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        try await store.installDefaultsIfNeeded()
        let names = (try await store.list()).map(\.name)
        #expect(Set(names) == Set(["Today", "This Week", "No Tags", "Recently Closed", "Stale"]))
    }

    @Test("Second invocation is a no-op (idempotent)")
    func secondRunNoOp() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        try await store.installDefaultsIfNeeded()
        let firstCount = try await store.list().count
        try await store.installDefaultsIfNeeded()
        let secondCount = try await store.list().count
        #expect(firstCount == secondCount)
    }

    @Test("Recreates only the deleted defaults when called again")
    func recreatesDeletedDefaults() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        try await store.installDefaultsIfNeeded()
        try await store.delete(byName: "Today")
        try await store.installDefaultsIfNeeded()
        let names = (try await store.list()).map(\.name)
        #expect(names.contains("Today"))
        #expect(names.filter { $0 == "Today" }.count == 1)
    }
}
