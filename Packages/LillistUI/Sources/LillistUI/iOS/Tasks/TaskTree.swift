// Cross-platform: shared by the iOS app and the macOS main window.
import Foundation
import LillistCore

/// Hierarchical projection of a flat `[TaskStore.TaskRecord]` list, used
/// by the iOS Tasks screen to render an outline view with collapsible
/// disclosure triangles.
///
/// Each node carries its `TaskRecord`, the tag names to render in its
/// row, and any children whose parent is also present in the input
/// records. Children whose parent is *not* in the input set are
/// promoted to the top level — matching the design rule that an
/// orphan-matched subtask renders flat when its parent isn't in the
/// current view.
public struct TaskNode: Identifiable, Hashable, Sendable {
    public let record: TaskStore.TaskRecord
    public let tagNames: [String]
    public let children: [TaskNode]

    public var id: UUID { record.id }

    public init(record: TaskStore.TaskRecord, tagNames: [String], children: [TaskNode]) {
        self.record = record
        self.tagNames = tagNames
        self.children = children
    }

    // Hashable cannot be synthesized because `TaskRecord` is only
    // `Equatable`. Identity-based hashing is correct here — `id` is a
    // unique UUID across the tree, and `record == record` already
    // covers content equality via the synthesized `==`.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(record.id)
    }

    public static func == (lhs: TaskNode, rhs: TaskNode) -> Bool {
        lhs.record == rhs.record
            && lhs.tagNames == rhs.tagNames
            && lhs.children == rhs.children
    }
}

public enum TaskTree {
    /// Build a hierarchical projection of `records`. Sort is applied
    /// per-level so the tree shape is preserved regardless of which
    /// option is active.
    public static func build(
        records: [TaskStore.TaskRecord],
        tagsByTask: [UUID: [String]],
        sort: TasksSort
    ) -> [TaskNode] {
        let presentIDs = Set(records.map(\.id))
        var childrenByParent: [UUID: [TaskStore.TaskRecord]] = [:]
        var rootRecords: [TaskStore.TaskRecord] = []
        rootRecords.reserveCapacity(records.count)

        for record in records {
            if let parent = record.parentID, presentIDs.contains(parent) {
                childrenByParent[parent, default: []].append(record)
            } else {
                // Either a real root (parentID == nil) or an orphan whose
                // parent is filtered out — promote to top level.
                rootRecords.append(record)
            }
        }

        func makeNode(from record: TaskStore.TaskRecord) -> TaskNode {
            let kids = (childrenByParent[record.id] ?? [])
            let sortedKids = applySort(kids, sort: sort).map(makeNode)
            return TaskNode(
                record: record,
                tagNames: tagsByTask[record.id] ?? [],
                children: sortedKids
            )
        }

        return applySort(rootRecords, sort: sort).map(makeNode)
    }

    private static func applySort(
        _ records: [TaskStore.TaskRecord],
        sort: TasksSort
    ) -> [TaskStore.TaskRecord] {
        switch sort {
        case .personalized:
            return records.sorted {
                SiblingOrder.precedes(
                    positionA: $0.position, idA: $0.id,
                    positionB: $1.position, idB: $1.id
                )
            }
        case .due:
            return records.sorted { lhs, rhs in
                switch (lhs.deadline, rhs.deadline) {
                case let (l?, r?):
                    if l != r { return l < r }
                    return lhs.id.uuidString < rhs.id.uuidString
                case (nil, _?): return false  // nil sorts last
                case (_?, nil): return true
                case (nil, nil):
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            }
        case .modified:
            return records.sorted { lhs, rhs in
                switch (lhs.modifiedAt, rhs.modifiedAt) {
                case let (l?, r?):
                    if l != r { return l > r }  // most-recent first
                    return lhs.id.uuidString < rhs.id.uuidString
                case (nil, _?): return false  // nil sorts last
                case (_?, nil): return true
                case (nil, nil):
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            }
        }
    }
}
