import Testing
import CoreData
import Foundation
@testable import LillistCore

/// T18 mirror tests — heal-then-recheck parity for `SmartFilterStore.reorder`.
///
/// Mirrors the structure of `TaskStoreReorderHealTests` (T2, T3, T4, T9, T6)
/// against `SmartFilterStore`. SmartFilter has no `deletedAt`, so the
/// soft-deleted-anchor guard variant (T7/T10) is omitted.
///
/// - T18a: equal-position pair heals (mirrors T2)
/// - T18b: genuinely inverted anchors still throw (mirrors T4/T6)
/// - T18c: `list()` returns filters in canonical `SiblingOrder` (mirrors T9)
@Suite("SmartFilterStore reorder heal", .serialized)
struct SmartFilterStoreReorderHealTests {

    // MARK: - Helpers

    private func emptyGroup() -> PredicateGroup {
        PredicateGroup(combinator: .all, predicates: [])
    }

    /// Force `position` on a SmartFilter identified by `id` directly via the
    /// `viewContext`, bypassing the store's public API.  Must be called
    /// outside of any existing `perform` block.
    private func forcePosition(
        _ newPosition: Double,
        forFilterID filterID: UUID,
        in ctx: NSManagedObjectContext
    ) async throws {
        try await ctx.perform {
            let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
            req.predicate = NSPredicate(format: "id == %@", filterID as CVarArg)
            req.fetchLimit = 1
            guard let obj = try ctx.fetch(req).first else {
                throw LillistError.notFound
            }
            obj.position = newPosition
            try ctx.save()
        }
    }

    // MARK: - T18a: Equal-position pair heals

    /// Two SmartFilters share the same position (a tie). Dragging a third filter
    /// into the gap between them should heal silently — not throw.
    ///
    /// Mirrors T2 (`healsEqualTailPair`) from `TaskStoreReorderHealTests`.
    @Test("T18a: equal-position pair — reorder into the gap heals and lands in intended slot")
    func healsEqualPositionPair() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        let ctx = p.container.viewContext

        // Create A, B, C — positions 1.0, 2.0, 3.0 initially.
        let aID = try await store.create(name: "FilterA", group: emptyGroup())
        let bID = try await store.create(name: "FilterB", group: emptyGroup())
        let cID = try await store.create(name: "FilterC", group: emptyGroup())

        // Force a tie: set B.position = 3.0 so B and C are both at 3.0.
        try await forcePosition(3.0, forFilterID: bID, in: ctx)

        // State: A=1.0, B=3.0, C=3.0 (B and C tied).
        // Drag A into the gap between tied B and C.
        // Must NOT throw; A must land after B in list order.
        try await store.reorder(id: aID, after: bID, before: cID)

        let list = try await store.list()
        let positions = list.map(\.position)

        // Positions must be strictly increasing after heal.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1],
                    "positions should be strictly increasing after heal")
        }

        // A must appear after B in the returned list.
        let bIdx = try #require(list.firstIndex(where: { $0.id == bID }))
        let aIdx = try #require(list.firstIndex(where: { $0.id == aID }))
        #expect(aIdx > bIdx, "A should land after B")
    }

    // MARK: - T18b: Genuinely inverted anchors still throw

    /// When SmartFilter anchors are genuinely inverted (after.position >
    /// before.position), `reorder` must still throw `LillistError` — the heal
    /// path must not mask real data-integrity violations.
    ///
    /// Mirrors T4 (`invertedAnchorStillThrows`) from `TaskStoreReorderHealTests`.
    @Test("T18b: genuinely inverted anchors still throw after restructure")
    func invertedStillThrows() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        let ctx = p.container.viewContext

        let aID = try await store.create(name: "FilterA", group: emptyGroup())
        let bID = try await store.create(name: "FilterB", group: emptyGroup())
        let cID = try await store.create(name: "FilterC", group: emptyGroup())

        // Force A to a position much higher than B — creating a genuine inversion.
        try await forcePosition(9.0, forFilterID: aID, in: ctx)
        // A=9.0, B=2.0, C=3.0 → asking to drop C with after=A, before=B is inverted.

        await #expect(throws: LillistError.self) {
            try await store.reorder(id: cID, after: aID, before: bID)
        }
    }

    // MARK: - T18c: list() returns filters in canonical SiblingOrder

    /// `list()` must return SmartFilters in canonical `SiblingOrder` — position
    /// ascending, then `id.uuidString` ascending on ties — not in the order Core
    /// Data happens to return them.
    ///
    /// Mirrors T9 (`tieBreakByIdNotCreatedAt`) from `TaskStoreReorderHealTests`.
    @Test("T18c: list() returns filters in SiblingOrder (position asc, id.uuidString asc on ties)")
    func listOrderIsCanonical() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        let ctx = p.container.viewContext

        // loID sorts before hiID in uuidString lexical order.
        let loID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let hiID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        // Insert filters directly so we control the UUIDs.
        // Insert hiID FIRST (earlier createdAt) then loID (later createdAt)
        // so that createdAt order is [hi, lo] but id.uuidString order is [lo, hi].
        let json = try SmartFilterStore.encode(PredicateGroup(combinator: .all, predicates: []))
        try await ctx.perform {
            // Y(hi) — earlier createdAt, later in uuidString sort.
            let yFilter = SmartFilter(context: ctx)
            yFilter.id = hiID
            yFilter.name = "Y(hi)"
            yFilter.predicateGroupJSON = json
            yFilter.sortField = .deadline
            yFilter.sortAscending = true
            yFilter.isPinned = false
            yFilter.position = 5.0
            yFilter.createdAt = Date(timeIntervalSinceReferenceDate: 1000)
            yFilter.modifiedAt = yFilter.createdAt

            // X(lo) — later createdAt, earlier in uuidString sort.
            let xFilter = SmartFilter(context: ctx)
            xFilter.id = loID
            xFilter.name = "X(lo)"
            xFilter.predicateGroupJSON = json
            xFilter.sortField = .deadline
            xFilter.sortAscending = true
            xFilter.isPinned = false
            xFilter.position = 5.0
            xFilter.createdAt = Date(timeIntervalSinceReferenceDate: 2000)
            xFilter.modifiedAt = xFilter.createdAt

            try ctx.save()
        }

        // Also add a normal filter at a lower position to verify position ordering.
        let aID = try await store.create(name: "FilterA", group: emptyGroup())
        try await forcePosition(1.0, forFilterID: aID, in: ctx)

        let list = try await store.list()

        // Verify the result is sorted according to SiblingOrder.precedes for all pairs.
        for i in 1..<list.count {
            let prev = list[i - 1]
            let curr = list[i]
            guard let prevID = UUID(uuidString: prev.id.uuidString),
                  let currID = UUID(uuidString: curr.id.uuidString) else { continue }
            let prevPrecedes = SiblingOrder.precedes(
                positionA: prev.position, idA: prevID,
                positionB: curr.position, idB: currID
            )
            #expect(prevPrecedes,
                    "list()[i-1] should precede list()[i] in SiblingOrder at index \(i)")
        }

        // The tied pair (X=lo, Y=hi both at 5.0) must appear in id.uuidString order.
        let xRec = try #require(list.first(where: { $0.id == loID }))
        let yRec = try #require(list.first(where: { $0.id == hiID }))
        let xIdx = try #require(list.firstIndex(where: { $0.id == loID }))
        let yIdx = try #require(list.firstIndex(where: { $0.id == hiID }))
        #expect(xRec.position == yRec.position, "X and Y should still have equal positions")
        #expect(xIdx < yIdx, "X(loID) should appear before Y(hiID) in list() — id.uuidString tie-break")
    }
}
