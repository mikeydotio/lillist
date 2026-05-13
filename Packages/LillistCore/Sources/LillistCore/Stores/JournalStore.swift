import Foundation
import CoreData

public final class JournalStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct JournalRecord: Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID
        public var kind: JournalEntryKind
        public var body: String
        public var payload: Data?
        public var createdAt: Date?
        public var editedAt: Date?
    }

    public func entries(forTask taskID: UUID) async throws -> [JournalRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    static func record(from m: JournalEntry) -> JournalRecord {
        JournalRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            kind: m.kind,
            body: m.body ?? "",
            payload: m.payload,
            createdAt: m.createdAt,
            editedAt: m.editedAt
        )
    }
}
