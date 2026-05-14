import AppIntents
import Foundation
import LillistCore

/// AppEntity surfaced to Shortcuts / Lock Screen / Spotlight. Built from
/// the value-type `TaskStore.TaskRecord`; no NSManagedObject crosses this
/// boundary (matches the project rule "No NSManagedObject escapes
/// LillistCore").
struct TaskEntity: AppEntity, Identifiable {
    let id: UUID
    @Property(title: "Title") var title: String
    @Property(title: "Status") var status: StatusAppEnum
    @Property(title: "Deadline") var deadline: Date?

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(StatusAppEnum.caseDisplayRepresentations[status]?.title ?? "")"
        )
    }

    static var defaultQuery = TaskEntityQuery()

    init(id: UUID, title: String, status: StatusAppEnum, deadline: Date?) {
        self.id = id
        self.title = title
        self.status = status
        self.deadline = deadline
    }
}

extension TaskEntity {
    init(_ record: TaskStore.TaskRecord) {
        self.init(
            id: record.id,
            title: record.title,
            status: StatusAppEnum(record.status),
            deadline: record.deadline
        )
    }
}
