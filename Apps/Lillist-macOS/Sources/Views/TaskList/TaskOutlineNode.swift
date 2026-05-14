import Foundation
import LillistCore

struct TaskOutlineNode: Identifiable, Hashable {
    let id: UUID
    let record: TaskStore.TaskRecord
    var children: [TaskOutlineNode]?
}
