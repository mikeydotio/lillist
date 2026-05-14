import Foundation
import CoreData

public final class JournalStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    /// Optional breadcrumb sink. See Plan 9 / design Section 8.
    public var breadcrumbs: BreadcrumbBuffer?

    fileprivate func recordCrumb(_ action: String, success: Bool) async {
        if let b = breadcrumbs {
            try? await b.record(action: action, success: success)
        }
    }

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

    // MARK: - Append

    @discardableResult
    public func appendNote(taskID: UUID, body: String) async throws -> UUID {
        defer { Task { [weak self] in await self?.recordCrumb("journal.append", success: true) } }
        return try await context.perform { [self] in
            let task = try fetchTask(id: taskID, in: context)
            let entry = JournalEntry(context: context)
            entry.id = UUID()
            entry.task = task
            entry.kind = .note
            entry.body = body
            entry.createdAt = Date()
            try context.save()
            return entry.id!
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> JournalRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return Self.record(from: m)
        }
    }

    public func entries(forTask taskID: UUID) async throws -> [JournalRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    // MARK: - Edit

    public func editNote(id: UUID, body: String) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.kind.isUserEditable else {
                throw LillistError.validationFailed([
                    .init(field: "kind", message: "system journal entries cannot be edited")
                ])
            }
            m.body = body
            m.editedAt = Date()
            try context.save()
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.kind.isUserEditable else {
                throw LillistError.validationFailed([
                    .init(field: "kind", message: "system journal entries cannot be deleted")
                ])
            }
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    private func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> JournalEntry {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    private func fetchTask(id: UUID, in ctx: NSManagedObjectContext) throws -> LillistTask {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
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
