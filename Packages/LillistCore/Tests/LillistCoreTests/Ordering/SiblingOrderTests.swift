import Testing
import Foundation
@testable import LillistCore

/// T1 suite: canonical sibling comparator.
///
/// `SiblingOrder` is the single source of truth for how siblings are
/// ordered: position ascending, then `id.uuidString` ascending on a tie.
/// These tests are RED until `Ordering/SiblingOrder.swift` is created.
@Suite("SiblingOrder")
struct SiblingOrderTests {

    // MARK: - T1.1  Distinct positions

    @Test("Distinct positions: lower position precedes higher")
    func distinctPositions_sortsByPosition() {
        let a = UUID()
        let b = UUID()
        // positionA < positionB → true
        #expect(SiblingOrder.precedes(positionA: 1.0, idA: a,
                                      positionB: 2.0, idB: b) == true)
        // positionA > positionB → false
        #expect(SiblingOrder.precedes(positionA: 2.0, idA: a,
                                      positionB: 1.0, idB: b) == false)
    }

    // MARK: - T1.2  Tie-break by id.uuidString

    @Test("Equal positions: lexicographically-lower UUID precedes higher UUID")
    func equalPositions_sortsByIDString() {
        // "00...01" < "FF...FF" lexicographically, so loID precedes hiID.
        let loID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let hiID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        // Pre-condition: our fixture truly satisfies the lexicographic ordering.
        #expect(loID.uuidString < hiID.uuidString)

        #expect(SiblingOrder.precedes(positionA: 5.0, idA: loID,
                                      positionB: 5.0, idB: hiID) == true)
        #expect(SiblingOrder.precedes(positionA: 5.0, idA: hiID,
                                      positionB: 5.0, idB: loID) == false)
    }
}
