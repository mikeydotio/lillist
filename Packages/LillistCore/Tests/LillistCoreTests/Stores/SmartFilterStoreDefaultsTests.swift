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

    // MARK: - Deduplication (CloudKit seed-race cleanup)

    private static var sampleGroup: PredicateGroup {
        PredicateGroup(
            combinator: .all,
            predicates: [.leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))]
        )
    }

    @Test("Collapses exact structural duplicates to a single survivor")
    func dedupCollapsesIdenticalFilters() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        for _ in 0..<4 {
            _ = try await store.create(name: "Today", group: Self.sampleGroup, sortField: .deadline, sortAscending: true)
        }
        #expect(try await store.list().count == 4)

        try await store.deduplicateExactDuplicates()

        let remaining = try await store.list()
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "Today")
    }

    @Test("Leaves structurally distinct same-name filters untouched")
    func dedupKeepsDistinctFilters() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        // Same name, but a different sort — a genuine user variation, not a dupe.
        _ = try await store.create(name: "Today", group: Self.sampleGroup, sortField: .deadline, sortAscending: true)
        _ = try await store.create(name: "Today", group: Self.sampleGroup, sortField: .title, sortAscending: false)

        try await store.deduplicateExactDuplicates()

        #expect(try await store.list().count == 2)
    }

    @Test("Prefers the pinned row as the dedup survivor")
    func dedupPrefersPinnedSurvivor() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        _ = try await store.create(name: "Today", group: Self.sampleGroup, sortField: .deadline, sortAscending: true)
        let b = try await store.create(name: "Today", group: Self.sampleGroup, sortField: .deadline, sortAscending: true)
        try await store.setPinned(id: b, pinned: true)

        try await store.deduplicateExactDuplicates()

        let remaining = try await store.list()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == b)   // the pinned duplicate survives
    }

    @Test("installDefaultsIfNeeded collapses pre-existing duplicate defaults")
    func installCollapsesDuplicateDefaults() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        // Two full rounds of raw defaults, mimicking the CloudKit seed race.
        for spec in DefaultSmartFilters.all + DefaultSmartFilters.all {
            _ = try await store.create(
                name: spec.name,
                group: spec.group,
                tintColor: spec.tintColor,
                sortField: spec.sortField,
                sortAscending: spec.sortAscending
            )
        }
        #expect(try await store.list().count == 10)

        try await store.installDefaultsIfNeeded()

        let names = (try await store.list()).map(\.name)
        #expect(names.count == 5)
        #expect(Set(names) == Set(["Today", "This Week", "No Tags", "Recently Closed", "Stale"]))
    }
}
