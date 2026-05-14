import Foundation
import LillistCore

struct TaskOutlineNode: Identifiable, Hashable {
    let id: UUID
    let record: TaskStore.TaskRecord
    var children: [TaskOutlineNode]?

    static func == (lhs: TaskOutlineNode, rhs: TaskOutlineNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
