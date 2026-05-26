#if os(iOS)
import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("TaskTree")
struct TaskTreeTests {

    // MARK: - Fixtures

    private func record(
        _ title: String,
        id: UUID,
        parent: UUID? = nil,
        position: Double = 0,
        deadline: Date? = nil,
        modifiedAt: Date? = nil
    ) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id,
            title: title,
            notes: "",
            status: .todo,
            start: nil, startHasTime: false,
            deadline: deadline, deadlineHasTime: deadline != nil,
            position: position,
            isPinned: false,
            parentID: parent,
            createdAt: nil,
            modifiedAt: modifiedAt,
            closedAt: nil,
            deletedAt: nil
        )
    }

    private static let parentA = UUID()
    private static let parentB = UUID()
    private static let childA1 = UUID()
    private static let childA2 = UUID()
    private static let childB1 = UUID()
    private static let orphanX = UUID()
    private static let ghostParent = UUID()  // referenced as parent but absent from set

    // MARK: - Structure

    @Test("Roots are records with nil parentID")
    func rootsHaveNilParent() {
        let records = [
            record("A", id: Self.parentA),
            record("B", id: Self.parentB)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        #expect(roots.map(\.record.title).sorted() == ["A", "B"])
        #expect(roots.allSatisfy { $0.children.isEmpty })
    }

    @Test("Children are nested under their parent when both are present")
    func childrenNestUnderParent() {
        let records = [
            record("A", id: Self.parentA),
            record("A1", id: Self.childA1, parent: Self.parentA),
            record("A2", id: Self.childA2, parent: Self.parentA),
            record("B", id: Self.parentB)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        let a = roots.first { $0.record.id == Self.parentA }
        #expect(a?.children.map(\.record.title).sorted() == ["A1", "A2"])
        let b = roots.first { $0.record.id == Self.parentB }
        #expect(b?.children.isEmpty == true)
    }

    @Test("Orphan subtasks (parent absent) are promoted to top level")
    func orphanedChildrenPromoted() {
        let records = [
            record("Orphan", id: Self.orphanX, parent: Self.ghostParent),
            record("A", id: Self.parentA)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        #expect(roots.map(\.record.title).sorted() == ["A", "Orphan"])
    }

    @Test("tagsByTask map flows through into TaskNode.tagNames")
    func tagsByTaskFlowsThrough() {
        let records = [record("A", id: Self.parentA)]
        let tags = [Self.parentA: ["work", "urgent"]]
        let roots = TaskTree.build(records: records, tagsByTask: tags, sort: .personalized)
        #expect(roots.first?.tagNames == ["work", "urgent"])
    }

    // MARK: - Sort

    @Test("Personalized sort uses position ascending at every level")
    func personalizedSortsByPositionAscending() {
        let records = [
            record("A", id: Self.parentA, position: 2),
            record("B", id: Self.parentB, position: 1),
            record("A2", id: Self.childA2, parent: Self.parentA, position: 5),
            record("A1", id: Self.childA1, parent: Self.parentA, position: 3)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        #expect(roots.map(\.record.title) == ["B", "A"])
        let a = roots.first { $0.record.id == Self.parentA }
        #expect(a?.children.map(\.record.title) == ["A1", "A2"])
    }

    @Test("Due sort puts soonest first; nil deadlines last at every level")
    func dueSortSoonestFirstNilLast() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let later = now.addingTimeInterval(86_400)
        let records = [
            record("NoDeadlineRoot", id: UUID()),
            record("LaterRoot", id: UUID(), deadline: later),
            record("SoonerRoot", id: UUID(), deadline: now)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .due)
        #expect(roots.map(\.record.title) == ["SoonerRoot", "LaterRoot", "NoDeadlineRoot"])
    }

    @Test("Modified sort puts most-recent first; nil modifiedAt last")
    func modifiedSortMostRecentFirst() {
        let older = Date(timeIntervalSince1970: 1_000_000_000)
        let newer = Date(timeIntervalSince1970: 1_780_000_000)
        let records = [
            record("Older", id: UUID(), modifiedAt: older),
            record("Newest", id: UUID(), modifiedAt: newer),
            record("Unset", id: UUID(), modifiedAt: nil)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .modified)
        #expect(roots.map(\.record.title) == ["Newest", "Older", "Unset"])
    }

    @Test("Sort applies recursively per level — children re-sorted independently of roots")
    func sortRecursesIntoChildren() {
        let records = [
            record("Parent", id: Self.parentA, position: 1),
            record("ChildLater", id: Self.childA1, parent: Self.parentA, position: 9),
            record("ChildSooner", id: Self.childA2, parent: Self.parentA, position: 2)
        ]
        let roots = TaskTree.build(records: records, tagsByTask: [:], sort: .personalized)
        let parent = roots.first
        #expect(parent?.children.map(\.record.title) == ["ChildSooner", "ChildLater"])
    }
}
#endif
