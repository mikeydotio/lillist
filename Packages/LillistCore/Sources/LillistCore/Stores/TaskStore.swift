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

    /// Page size for list fetches. Core Data returns rows as faults in
    /// pages of this size and only realizes each page when touched, so a
    /// reload over a large sibling set doesn't fault+project every row on
    /// the main-queue `viewContext` at once. See the foundation review's
    /// "unbounded TaskStore fetch" finding and `docs/engineering-notes.md`.
    static let listFetchBatchSize = 100

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
        public var archivedAt: Date?
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
            archivedAt: Date? = nil,
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
            self.archivedAt = archivedAt
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
            await context.perform { [self] in context.rollback() }
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
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.update", success: false)
            throw error
        }
    }

    // MARK: - Hard delete

    public func hardDelete(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                context.delete(m)
                try context.save()
            }
            await recordCrumb("task.purge", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.purge", success: false)
            throw error
        }
    }

    // MARK: - Hierarchy

    public func children(of parentID: UUID?) async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = try childrenFetchRequest(parentID: parentID, in: context)
            return try context.fetch(req).map(record(from:))
        }
    }

    /// Paged variant of `children(of:)`. Returns at most `limit` rows
    /// starting at `offset`, in the same `position`/`createdAt` order.
    ///
    /// The UI uses this so a reload faults and DTO-projects only the
    /// visible window instead of the whole sibling set (see the
    /// `fetchBatchSize` policy in `docs/engineering-notes.md`). `offset`
    /// beyond the end yields an empty array; `limit <= 0` is treated as
    /// "no limit" (parity with `NSFetchRequest.fetchLimit == 0`).
    public func children(of parentID: UUID?, limit: Int, offset: Int) async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = try childrenFetchRequest(parentID: parentID, in: context)
            req.fetchLimit = max(0, limit)
            req.fetchOffset = max(0, offset)
            return try context.fetch(req).map(record(from:))
        }
    }

    /// Shared builder for the `children` fetch. `fetchBatchSize` makes Core
    /// Data return faults in pages of `Self.listFetchBatchSize` and only
    /// realize each page as it's touched — so even the unbounded overload no
    /// longer fully materializes a huge sibling set up front. Must be called
    /// inside `context.perform`.
    private func childrenFetchRequest(parentID: UUID?, in ctx: NSManagedObjectContext) throws -> NSFetchRequest<LillistTask> {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parentID {
            let parent = try fetchManagedObject(id: parentID, in: ctx)
            req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
        }
        req.sortDescriptors = [
            NSSortDescriptor(key: "position", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        req.fetchBatchSize = Self.listFetchBatchSize
        return req
    }

    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        do {
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
            await recordCrumb("task.move", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.move", success: false)
            throw error
        }
    }

    // MARK: - Reorder

    public func reorder(id: UUID, after afterID: UUID?, before beforeID: UUID?) async throws {
        do {
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
                if FractionalPosition.anchorsAreOutOfOrder(
                    after: afterTask?.position,
                    before: beforeTask?.position
                ) {
                    throw LillistError.validationFailed([
                        .init(field: "neighbors", message: "anchors out of order")
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

                // If the target gap underflows, re-space all siblings evenly,
                // then recompute against the freshly-spaced neighbors. Recompaction
                // and the target update persist together in this one perform block.
                if FractionalPosition.needsCompaction(
                    after: afterTask?.position,
                    before: beforeTask?.position
                ) {
                    recompactSiblings(ofParent: newParent)
                }

                m.position = FractionalPosition.position(
                    after: afterTask?.position,
                    before: beforeTask?.position
                )
                m.modifiedAt = Date()
                try context.save()
            }
        } catch {
            await context.perform { [self] in context.rollback() }
            throw error
        }
    }

    // MARK: - Status transitions

    public func transition(id: UUID, to newStatus: Status) async throws {
        do {
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
                    // Reopening a previously archived task resurfaces it —
                    // a user explicitly un-completing is the signal that
                    // they want it back in the active view.
                    m.archivedAt = nil
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
            await recordCrumb("task.status.change", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.status.change", success: false)
            throw error
        }
    }

    // MARK: - Archive

    /// Stamp `archivedAt = now` on every task in `ids` that doesn't already
    /// have a value. Returns just the IDs that were actually flipped, so
    /// callers (notably the iOS pull-to-refresh undo affordance) can scope
    /// "undo" to the rows their action created without trampling earlier
    /// archive batches.
    ///
    /// Note: archive is independent of status. Closing a task does not
    /// auto-archive it; the UI batches and archives explicitly. Reopening a
    /// closed task does, however, clear `archivedAt` (see `transition`).
    @discardableResult
    public func archive(ids: [UUID]) async throws -> [UUID] {
        do {
            let affected: [UUID] = try await context.perform { [self] in
                var flipped: [UUID] = []
                let now = Date()
                for id in ids {
                    let m = try fetchManagedObject(id: id, in: context)
                    guard m.archivedAt == nil else { continue }
                    m.archivedAt = now
                    m.modifiedAt = now
                    flipped.append(id)
                }
                try context.save()
                return flipped
            }
            await recordCrumb("task.archive", success: true)
            return affected
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.archive", success: false)
            throw error
        }
    }

    /// Clear `archivedAt` on every task in `ids`. Idempotent — rows already
    /// at `archivedAt == nil` are left untouched.
    public func unarchive(ids: [UUID]) async throws {
        do {
            try await context.perform { [self] in
                for id in ids {
                    let m = try fetchManagedObject(id: id, in: context)
                    guard m.archivedAt != nil else { continue }
                    m.archivedAt = nil
                    m.modifiedAt = Date()
                }
                try context.save()
            }
            await recordCrumb("task.unarchive", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.unarchive", success: false)
            throw error
        }
    }

    // MARK: - Soft delete

    public func softDelete(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let now = Date()
                applySoftDelete(to: m, at: now)
                try context.save()
            }
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.delete", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.delete", success: false)
            throw error
        }
    }

    public func restore(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                guard let deletedAt = m.deletedAt else { return }
                clearSoftDelete(from: m, matchingDeletedAt: deletedAt)
                try context.save()
            }
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.restore", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.restore", success: false)
            throw error
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
            // `deletedAt != nil` takes no arguments, so the args array is empty.
            let count: Int = try await batchPurge(
                predicateFormat: "deletedAt != nil",
                arguments: []
            )
            await recordCrumb("task.purge_all", success: true)
            return count
        } catch {
            await recordCrumb("task.purge_all", success: false)
            throw error
        }
    }

    /// Hard-deletes every `LillistTask` matching `predicateFormat` off the
    /// main-queue `viewContext`, on a background context, in a single
    /// `NSBatchDeleteRequest`.
    ///
    /// The predicate is rebuilt *inside* the `@Sendable` background-context
    /// closure from its Sendable format string + argument list — an
    /// `NSPredicate` is not `Sendable` and so cannot be captured across the
    /// actor boundary (the same hoist-and-rebuild pattern `PersistenceHost`
    /// uses for `NSPersistentStoreDescription`).
    ///
    /// - Parameters:
    ///   - predicateFormat: `NSPredicate(format:)` string selecting the
    ///     victim rows.
    ///   - arguments: The substitution arguments for `predicateFormat`.
    ///     Must be `Sendable` so they survive the actor-boundary capture.
    /// - Returns: The number of `LillistTask` rows removed (roots plus every
    ///   cascade-reachable descendant task).
    private func batchPurge(
        predicateFormat: String,
        arguments: [any Sendable]
    ) async throws -> Int {
        let ctx = persistence.makeBackgroundContext()
        let viewContext = persistence.container.viewContext
        let deletedIDs: [NSManagedObjectID] = try await ctx.perform {
            let predicate = NSPredicate(
                format: predicateFormat,
                argumentArray: arguments
            )
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = predicate
            let matched = try ctx.fetch(req)
            let roots = matched.filter { task in
                guard let parent = task.parent else { return true }
                return !predicate.evaluate(with: parent)
            }
            // `NSBatchDeleteRequest` bypasses Core Data's Cascade delete
            // rules, so expand each root to every cascade-reachable
            // objectID (descendants, journal entries, attachments,
            // notification specs), then delete that closure entity-by-entity
            // (a single batch is restricted to one entity). The returned IDs
            // are merged into the viewContext below so it invalidates the
            // corresponding in-memory objects and callers see no dangling
            // faults.
            let ids = CascadeReaper.objectIDs(forDeleting: roots)
            return try CascadeReaper.batchDelete(objectIDs: ids, in: ctx)
        }
        guard !deletedIDs.isEmpty else { return 0 }
        await viewContext.perform {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
                into: [viewContext]
            )
        }
        return await ctx.perform {
            deletedIDs.filter { $0.entity.name == "LillistTask" }.count
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
        do {
            try await context.perform { [self] in
                let task = try fetchManagedObject(id: taskID, in: context)
                let tag = try fetchTag(id: tagID, in: context)
                let existing = task.tags as? Set<Tag> ?? []
                if existing.contains(tag) { return }
                task.addToTags(tag)
                task.modifiedAt = Date()
                try context.save()
            }
        } catch {
            await context.perform { [self] in context.rollback() }
            throw error
        }
    }

    public func unassignTag(taskID: UUID, tagID: UUID) async throws {
        do {
            try await context.perform { [self] in
                let task = try fetchManagedObject(id: taskID, in: context)
                let tag = try fetchTag(id: tagID, in: context)
                task.removeFromTags(tag)
                task.modifiedAt = Date()
                try context.save()
            }
        } catch {
            await context.perform { [self] in context.rollback() }
            throw error
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

    /// Re-space every non-trashed sibling under `parent` to even 1.0 gaps,
    /// preserving their current order. Mutates the managed objects in place;
    /// the caller's `context.save()` persists them. Must run inside the
    /// reorder `perform` block so recompaction and the target update commit
    /// atomically. The anchor managed objects the caller is holding pick up
    /// their new `position` values, so a post-recompaction
    /// `FractionalPosition.position` call sees the widened gaps.
    private func recompactSiblings(ofParent parent: LillistTask?) {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
        }
        req.sortDescriptors = [
            NSSortDescriptor(key: "position", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        guard let siblings = try? context.fetch(req) else { return }
        let respaced = PositionCompactor.recompact(positions: siblings.map(\.position))
        for (sibling, newPosition) in zip(siblings, respaced) {
            sibling.position = newPosition
        }
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
            archivedAt: m.archivedAt,
            deletedAt: m.deletedAt,
            seriesID: m.series?.id
        )
    }
}
