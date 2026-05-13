import Foundation
import CoreData

public final class TaskStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// A value-type DTO callers see — never an `NSManagedObject`.
    public struct TaskRecord: Sendable, Equatable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var status: Status
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var position: Double
        public var isPinned: Bool
        public var parentID: UUID?
        public var createdAt: Date?
        public var modifiedAt: Date?
        public var closedAt: Date?
        public var deletedAt: Date?
    }

    /// Mutable view passed to `update`'s closure.
    public struct TaskDraft {
        public var title: String
        public var notes: String
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var isPinned: Bool
    }

    // MARK: - Create

    @discardableResult
    public func create(
        title: String,
        notes: String = "",
        parent: UUID? = nil
    ) async throws -> UUID {
        try validateTitle(title)
        return try await context.perform { [self] in
            let task = LillistTask(context: context)
            let id = UUID()
            task.id = id
            task.title = title
            task.notes = notes
            task.status = .todo
            task.startHasTime = false
            task.deadlineHasTime = false
            task.isPinned = false
            task.createdAt = Date()
            task.modifiedAt = task.createdAt
            if let parent {
                let parentTask = try fetchManagedObject(id: parent, in: context)
                task.parent = parentTask
            }
            task.position = try nextPosition(forParent: task.parent)
            try context.save()
            return id
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> TaskRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return record(from: m)
        }
    }

    // MARK: - Update

    public func update(id: UUID, _ block: @escaping @Sendable (inout TaskDraft) -> Void) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            var draft = TaskDraft(
                title: m.title ?? "",
                notes: m.notes ?? "",
                start: m.start,
                startHasTime: m.startHasTime,
                deadline: m.deadline,
                deadlineHasTime: m.deadlineHasTime,
                isPinned: m.isPinned
            )
            block(&draft)
            try validateTitle(draft.title)
            m.title = draft.title
            m.notes = draft.notes
            m.start = draft.start
            m.startHasTime = draft.startHasTime
            m.deadline = draft.deadline
            m.deadlineHasTime = draft.deadlineHasTime
            m.isPinned = draft.isPinned
            m.modifiedAt = Date()
            try context.save()
        }
    }

    // MARK: - Hard delete

    public func hardDelete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Hierarchy

    public func children(of parentID: UUID?) async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            if let parentID {
                let parent = try fetchManagedObject(id: parentID, in: context)
                req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
            } else {
                req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
            }
            req.sortDescriptors = [
                NSSortDescriptor(key: "position", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            return try context.fetch(req).map(record(from:))
        }
    }

    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let newParent: LillistTask?
            if let newParentID {
                let candidate = try fetchManagedObject(id: newParentID, in: context)
                if Validators.wouldCreateCycle(candidate: m, newParent: candidate) {
                    throw LillistError.validationFailed([
                        .init(field: "parent", message: "would create a cycle")
                    ])
                }
                newParent = candidate
            } else {
                newParent = nil
            }
            m.parent = newParent
            m.position = try nextPosition(forParent: newParent)
            m.modifiedAt = Date()
            try context.save()
        }
    }

    // MARK: - Reorder

    public func reorder(id: UUID, after afterID: UUID?, before beforeID: UUID?) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let afterTask = try afterID.map { try fetchManagedObject(id: $0, in: context) }
            let beforeTask = try beforeID.map { try fetchManagedObject(id: $0, in: context) }

            let afterParent = afterTask?.parent
            let beforeParent = beforeTask?.parent
            if let a = afterTask, let b = beforeTask, a.parent?.objectID != b.parent?.objectID {
                throw LillistError.validationFailed([
                    .init(field: "neighbors", message: "must share the same parent")
                ])
            }
            let newParent = afterParent ?? beforeParent ?? m.parent

            if m.parent?.objectID != newParent?.objectID {
                if Validators.wouldCreateCycle(candidate: m, newParent: newParent) {
                    throw LillistError.validationFailed([
                        .init(field: "parent", message: "would create a cycle")
                    ])
                }
                m.parent = newParent
            }
            m.position = FractionalPosition.position(
                after: afterTask?.position,
                before: beforeTask?.position
            )
            m.modifiedAt = Date()
            try context.save()
        }
    }

    // MARK: - Status transitions

    public func transition(id: UUID, to newStatus: Status) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let oldStatus = m.status
            guard oldStatus != newStatus else { return }
            m.status = newStatus
            m.modifiedAt = Date()
            if newStatus == .closed {
                m.closedAt = m.modifiedAt
            } else if oldStatus == .closed {
                m.closedAt = nil
            }

            // System journal entry for the transition.
            let entry = JournalEntry(context: context)
            entry.id = UUID()
            entry.task = m
            entry.kind = .statusChange
            entry.createdAt = m.modifiedAt
            entry.body = "\(oldStatus) → \(newStatus)"
            let payload: [String: Int] = ["from": oldStatus.rawValue, "to": newStatus.rawValue]
            entry.payload = try JSONSerialization.data(withJSONObject: payload)

            // Recurrence: spawn next instance ONLY on transition-to-closed.
            // Re-opening (oldStatus == .closed) does NOT undo the spawn,
            // per design Section 8.
            if newStatus == .closed {
                RecurrenceSpawner.spawnIfNeeded(forClosedTask: m, in: context)
            }

            try context.save()
        }
    }

    // MARK: - Soft delete

    public func softDelete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let now = Date()
            applySoftDelete(to: m, at: now)
            try context.save()
        }
    }

    public func restore(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard let deletedAt = m.deletedAt else { return }
            clearSoftDelete(from: m, matchingDeletedAt: deletedAt)
            try context.save()
        }
    }

    public func trashed() async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil")
            req.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]
            return try context.fetch(req).map(record(from:))
        }
    }

    private func applySoftDelete(to m: LillistTask, at now: Date) {
        m.deletedAt = now
        m.modifiedAt = now
        if let children = m.children as? Set<LillistTask> {
            for child in children where child.deletedAt == nil {
                applySoftDelete(to: child, at: now)
            }
        }
    }

    private func clearSoftDelete(from m: LillistTask, matchingDeletedAt: Date) {
        m.deletedAt = nil
        m.modifiedAt = Date()
        if let children = m.children as? Set<LillistTask> {
            for child in children where child.deletedAt == matchingDeletedAt {
                clearSoftDelete(from: child, matchingDeletedAt: matchingDeletedAt)
            }
        }
    }

    // MARK: - Tags

    public func assignTag(taskID: UUID, tagID: UUID) async throws {
        try await context.perform { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tag = try fetchTag(id: tagID, in: context)
            let existing = task.tags as? Set<Tag> ?? []
            if existing.contains(tag) { return }
            task.addToTags(tag)
            task.modifiedAt = Date()
            try context.save()
        }
    }

    public func unassignTag(taskID: UUID, tagID: UUID) async throws {
        try await context.perform { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tag = try fetchTag(id: tagID, in: context)
            task.removeFromTags(tag)
            task.modifiedAt = Date()
            try context.save()
        }
    }

    public func tagIDs(forTask taskID: UUID) async throws -> [UUID] {
        try await context.perform { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tags = (task.tags as? Set<Tag>) ?? []
            return tags.compactMap(\.id)
        }
    }

    private func fetchTag(id: UUID, in ctx: NSManagedObjectContext) throws -> Tag {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    // MARK: - Helpers

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> LillistTask {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else {
            throw LillistError.notFound
        }
        return m
    }

    func nextPosition(forParent parent: LillistTask?) throws -> Double {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil")
        }
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: false)]
        req.fetchLimit = 1
        let lastPosition = try context.fetch(req).first?.position
        return FractionalPosition.position(after: lastPosition, before: nil)
    }

    func validateTitle(_ title: String) throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LillistError.validationFailed([
                .init(field: "title", message: "must not be empty")
            ])
        }
    }

    func record(from m: LillistTask) -> TaskRecord {
        TaskRecord(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start,
            startHasTime: m.startHasTime,
            deadline: m.deadline,
            deadlineHasTime: m.deadlineHasTime,
            position: m.position,
            isPinned: m.isPinned,
            parentID: m.parent?.id,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt,
            closedAt: m.closedAt,
            deletedAt: m.deletedAt
        )
    }
}
