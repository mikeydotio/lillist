import Foundation
import CoreData

public final class TaskStore: @unchecked Sendable {
    let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    /// Notification reconciler. Set by the app's composition root; left
    /// `nil` in tests that don't care about notifications, in which case
    /// the reconcile calls in mutation methods are no-ops.
    ///
    /// Property-injected (rather than init-injected) so the 100+ existing
    /// `TaskStore(persistence:)` test call sites continue to work without
    /// modification.
    public var notificationScheduler: (any NotificationReconciling)?

    /// Optional breadcrumb sink. When non-nil, successful and failed
    /// mutations record verb-only entries for crash diagnostics.
    /// See design Section 8 / Plan 9.
    public var breadcrumbs: BreadcrumbBuffer?

    /// Fire-and-forget breadcrumb recorder. Drops silently if the
    /// buffer rejects the verb (e.g. would-be PII in `action`).
    fileprivate func recordCrumb(_ action: String, success: Bool) async {
        if let b = breadcrumbs {
            try? await b.record(action: action, success: success)
        }
    }

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
        public var seriesID: UUID?

        public init(
            id: UUID,
            title: String,
            notes: String,
            status: Status,
            start: Date?,
            startHasTime: Bool,
            deadline: Date?,
            deadlineHasTime: Bool,
            position: Double,
            isPinned: Bool,
            parentID: UUID?,
            createdAt: Date?,
            modifiedAt: Date?,
            closedAt: Date?,
            deletedAt: Date?,
            seriesID: UUID? = nil
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.status = status
            self.start = start
            self.startHasTime = startHasTime
            self.deadline = deadline
            self.deadlineHasTime = deadlineHasTime
            self.position = position
            self.isPinned = isPinned
            self.parentID = parentID
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.closedAt = closedAt
            self.deletedAt = deletedAt
            self.seriesID = seriesID
        }
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
        do {
            try validateTitle(title)
            let id: UUID = try await context.perform { [self] in
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
            await recordCrumb("task.create", success: true)
            return id
        } catch {
            await recordCrumb("task.create", success: false)
            throw error
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
        do {
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
            // Anchor fields (start/deadline) and their time flags affect
            // notification scheduling. Reconcile after save.
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.update", success: true)
        } catch {
            await recordCrumb("task.update", success: false)
            throw error
        }
    }

    // MARK: - Hard delete

    public func hardDelete(id: UUID) async throws {
        defer { Task { [weak self] in await self?.recordCrumb("task.purge", success: true) } }
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
        defer { Task { [weak self] in await self?.recordCrumb("task.move", success: true) } }
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
        defer { Task { [weak self] in await self?.recordCrumb("task.status.change", success: true) } }
        let spawnedID: UUID? = try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let oldStatus = m.status
            guard oldStatus != newStatus else { return nil }
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
            var spawnedID: UUID? = nil
            if newStatus == .closed {
                spawnedID = RecurrenceSpawner.spawnIfNeeded(forClosedTask: m, in: context)
            }

            try context.save()
            return spawnedID
        }
        // Reconcile *after* the save so the persistent store reflects the
        // new state. The scheduler is property-injected; absent in tests
        // that don't care about notifications.
        if let scheduler = notificationScheduler {
            await scheduler.reconcile(taskID: id)
            if let spawnedID {
                await scheduler.reconcile(taskID: spawnedID)
            }
        }
    }

    // MARK: - Soft delete

    public func softDelete(id: UUID) async throws {
        defer { Task { [weak self] in await self?.recordCrumb("task.delete", success: true) } }
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let now = Date()
            applySoftDelete(to: m, at: now)
            try context.save()
        }
        if let scheduler = notificationScheduler {
            await scheduler.reconcile(taskID: id)
        }
    }

    public func restore(id: UUID) async throws {
        defer { Task { [weak self] in await self?.recordCrumb("task.restore", success: true) } }
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard let deletedAt = m.deletedAt else { return }
            clearSoftDelete(from: m, matchingDeletedAt: deletedAt)
            try context.save()
        }
        if let scheduler = notificationScheduler {
            await scheduler.reconcile(taskID: id)
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

    /// Hard-delete every task currently in the Trash (i.e. with
    /// `deletedAt != nil`), including any descendants. Returns the number
    /// of tasks removed. Plan 11 / design Section 7 ("Trash") — the
    /// "Empty Trash now" affordance in Preferences calls this.
    ///
    /// Distinct from `AutoPurgeJob`, which only removes tasks whose
    /// `deletedAt` is older than the retention window.
    @discardableResult
    public func purgeAll() async throws -> Int {
        do {
            let count: Int = try await context.perform { [self] in
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = NSPredicate(format: "deletedAt != nil")
                let trashed = try context.fetch(req)
                // Only count/iterate trashed roots — tasks whose parent isn't
                // itself trashed. Descendants are already cascade-soft-deleted
                // via `applySoftDelete`, so iterating every trashed row would
                // double-count children once via `countDescendants(of: parent)`
                // and again when the child appears in `trashed` directly.
                let trashedRoots = trashed.filter { $0.parent?.deletedAt == nil }
                var count = 0
                for t in trashedRoots {
                    count += 1 + countDescendants(of: t)
                    context.delete(t) // cascades to children via the Core Data rule
                }
                try context.save()
                return count
            }
            await recordCrumb("task.purge_all", success: true)
            return count
        } catch {
            await recordCrumb("task.purge_all", success: false)
            throw error
        }
    }

    private func countDescendants(of t: LillistTask) -> Int {
        guard let kids = t.children as? Set<LillistTask>, !kids.isEmpty else { return 0 }
        return kids.reduce(0) { $0 + 1 + countDescendants(of: $1) }
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
            deletedAt: m.deletedAt,
            seriesID: m.series?.id
        )
    }
}
