import Testing
import Foundation
@testable import LillistCore

@Suite("DefaultsInstaller")
struct DefaultsInstallerTests {
    @Test("First run installs all five defaults")
    func firstRunInstalls() async throws {
        let p = try await TestStore.make()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        let names = try await filters.list().map(\.name).sorted()
        #expect(names == ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }

    @Test("Second run is a no-op — exactly five filters remain")
    func secondRunIdempotent() async throws {
        let p = try await TestStore.make()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        try await installer.installIfNeeded()
        let count = try await filters.list().count
        #expect(count == 5)
    }

    @Test("Missing filter is restored without duplicating others")
    func restoresMissing() async throws {
        let p = try await TestStore.make()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        // Delete "Stale" — simulates user removing a default.
        let stale = try await filters.list().first { $0.name == "Stale" }
        #expect(stale != nil)
        try await filters.delete(id: stale!.id)
        try await installer.installIfNeeded()
        let names = try await filters.list().map(\.name).sorted()
        #expect(names == ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }

    @Test("Renamed default is treated as a user filter — new default is created")
    func renamedNotRecreated() async throws {
        let p = try await TestStore.make()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        let today = try await filters.list().first { $0.name == "Today" }!
        // SmartFilterStore exposes `update(id:_:)` rather than a dedicated
        // `rename` method; rename via the closure.
        try await filters.update(id: today.id) { $0.name = "My Today" }
        try await installer.installIfNeeded()
        let names = try await filters.list().map(\.name).sorted()
        // "Today" gets re-created because the installer matches on name
        // (acceptable: a renamed default behaves like a user filter).
        #expect(names == ["My Today", "No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }
}
