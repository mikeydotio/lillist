#if os(iOS)
import Testing
import Foundation
import LillistCore
@testable import LillistUI

/// T1.3  Parity test: `SiblingOrder.precedes` and `TaskTree.build` with
/// `.personalized` sort must produce identical ordering.
///
/// Three records exercise both sort paths:
///   A  position=1.0  (distinct — wins on position alone)
///   B  position=2.0  id="BBBB…" (tie with C; B < C lexicographically → B precedes C)
///   C  position=2.0  id="CCCC…" (tie with B; C > B lexicographically → C follows B)
///
/// Expected canonical order: A, B, C
///
/// This test is RED until `Ordering/SiblingOrder.swift` is created.
@Suite("SiblingOrder — parity with TaskTree.personalized")
struct SiblingOrderParityTests {

    // MARK: - Fixtures

    private static let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private static let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
    private static let idC = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000000")!

    private func makeRecord(id: UUID, position: Double) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id,
            title: id.uuidString,
            notes: "",
            status: .todo,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: position,
            isPinned: false,
            parentID: nil,
            createdAt: nil,
            modifiedAt: nil,
            closedAt: nil,
            deletedAt: nil
        )
    }

    // MARK: - T1.3

    @Test("SiblingOrder.precedes matches TaskTree(.personalized) for flat list")
    func parity_withTaskTree_personalized() {
        let recordA = makeRecord(id: Self.idA, position: 1.0)
        let recordB = makeRecord(id: Self.idB, position: 2.0)
        let recordC = makeRecord(id: Self.idC, position: 2.0)

        // Pre-condition: our UUID fixtures satisfy the expected lexicographic order.
        #expect(Self.idA.uuidString < Self.idB.uuidString)
        #expect(Self.idB.uuidString < Self.idC.uuidString)

        // --- Sort via SiblingOrder ---
        let siblingOrdered = [recordC, recordA, recordB].sorted {
            SiblingOrder.precedes(positionA: $0.position, idA: $0.id,
                                  positionB: $1.position, idB: $1.id)
        }
        let siblingIDs = siblingOrdered.map(\.id)

        // --- Sort via TaskTree.build(.personalized) ---
        let nodes = TaskTree.build(
            records: [recordC, recordA, recordB],
            tagsByTask: [:],
            sort: .personalized
        )
        let treeIDs = nodes.map(\.record.id)

        // Both must produce A, B, C.
        let expected = [Self.idA, Self.idB, Self.idC]
        #expect(siblingIDs == expected,
                "SiblingOrder produced \(siblingIDs) but expected \(expected)")
        #expect(treeIDs == expected,
                "TaskTree(.personalized) produced \(treeIDs) but expected \(expected)")
        #expect(siblingIDs == treeIDs,
                "SiblingOrder and TaskTree(.personalized) disagree: \(siblingIDs) vs \(treeIDs)")
    }
}
#endif
