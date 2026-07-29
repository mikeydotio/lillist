import Testing
import Foundation
import LillistCore
@testable import LillistUI

/// `L1`: the pinned-filter-chip row (`TasksView` on iOS, `MacTasksView` on
/// macOS) used to sort with a raw `.sorted { $0.position < $1.position }`
/// comparator, with no tie-break — unlike `SmartFilterStore.list()`'s own
/// canonical `SiblingOrder` (position ascending, then `id.uuidString`
/// ascending on ties), which every other filter-listing surface (Settings/
/// Preferences) uses. Two pinned filters sharing a position could render in
/// different relative order on the chip row than everywhere else. Both app
/// targets' duplicated sort logic is now consolidated into
/// `SavedFilterChipSpec.pinnedSorted(from:)`, which this suite pins
/// directly — genuinely cross-platform (no `#if os(iOS)`; `FilterHeader.swift`'s
/// own header comment says as much, unlike `SiblingOrderParityTests`' iOS-only gate).
@Suite("SavedFilterChipSpec.pinnedSorted (L1)")
struct SavedFilterChipSpecOrderingTests {
    private static let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private static let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
    private static let idC = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000000")!

    private func record(
        id: UUID,
        name: String,
        position: Double,
        isPinned: Bool = true
    ) -> SmartFilterStore.SmartFilterRecord {
        SmartFilterStore.SmartFilterRecord(
            id: id,
            name: name,
            group: .init(combinator: .all, predicates: []),
            tintColor: nil,
            sortField: .deadline,
            sortAscending: true,
            isPinned: isPinned,
            position: position
        )
    }

    @Test("Distinct positions sort by position, matching SiblingOrder directly")
    func distinctPositionsSortByPosition() {
        let filters = [
            record(id: Self.idC, name: "C", position: 3),
            record(id: Self.idA, name: "A", position: 1),
            record(id: Self.idB, name: "B", position: 2),
        ]
        let chips = SavedFilterChipSpec.pinnedSorted(from: filters)
        #expect(chips.map(\.id) == [Self.idA, Self.idB, Self.idC])
    }

    @Test("A position tie breaks by id.uuidString ascending — the exact SiblingOrder tie-break, not array/insertion order")
    func tiedPositionsBreakByIDLexically() {
        // idB < idC lexicographically (see the fixture pre-condition below).
        // Insert them in the OPPOSITE (C, then B) order, and with a THIRD,
        // distinctly-positioned filter interleaved, so a naive stable sort
        // over position alone could plausibly still "accidentally" preserve
        // input order for the tie — this fixture doesn't let that happen.
        #expect(Self.idB.uuidString < Self.idC.uuidString)
        let filters = [
            record(id: Self.idC, name: "C", position: 5),
            record(id: Self.idA, name: "A", position: 1),
            record(id: Self.idB, name: "B", position: 5),
        ]
        let chips = SavedFilterChipSpec.pinnedSorted(from: filters)
        #expect(chips.map(\.id) == [Self.idA, Self.idB, Self.idC], "tied positions must break by id.uuidString ascending (B before C), independent of input array order")
    }

    @Test("Matches SmartFilterStore's own SiblingOrder.precedes exactly, for the same fixture")
    func matchesSiblingOrderPrecedesDirectly() {
        let filters = [
            record(id: Self.idC, name: "C", position: 2),
            record(id: Self.idA, name: "A", position: 1),
            record(id: Self.idB, name: "B", position: 2),
        ]
        let chips = SavedFilterChipSpec.pinnedSorted(from: filters)
        let viaSiblingOrder = filters.sorted {
            SiblingOrder.precedes(positionA: $0.position, idA: $0.id, positionB: $1.position, idB: $1.id)
        }
        #expect(chips.map(\.id) == viaSiblingOrder.map(\.id))
    }

    @Test("Unpinned filters are excluded")
    func unpinnedFiltersExcluded() {
        let filters = [
            record(id: Self.idA, name: "A", position: 1, isPinned: true),
            record(id: Self.idB, name: "B", position: 2, isPinned: false),
        ]
        let chips = SavedFilterChipSpec.pinnedSorted(from: filters)
        #expect(chips.map(\.id) == [Self.idA])
    }
}
