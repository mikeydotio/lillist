import Foundation
import UniformTypeIdentifiers
import CoreTransferable

public struct TaskDragPayload: Codable, Transferable, Sendable {
    public var taskID: UUID
    public init(taskID: UUID) { self.taskID = taskID }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .lillistTask)
    }
}

public extension UTType {
    static let lillistTask = UTType(exportedAs: "io.mikeydotio.Lillist.task")
}
