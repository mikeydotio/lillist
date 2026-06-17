import Foundation
import CoreData

/// CRUD over `NotificationSpec` rows. Pure persistence — no scheduling
/// side effects. The `NotificationScheduler` is what reacts to changes; the
/// store is just persistence.
public final class NotificationSpecStore: @unchecked Sendable {
    let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct SpecRecord: Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID
        public var kind: NotificationKind
        public var offsetMinutes: Int32?
        public var fireDate: Date?
        public var lastFiredAt: Date?
        public var snoozedUntil: Date?
        public var createdAt: Date?

        public init(
            id: UUID,
            taskID: UUID,
            kind: NotificationKind,
            offsetMinutes: Int32?,
            fireDate: Date?,
            lastFiredAt: Date?,
            snoozedUntil: Date?,
            createdAt: Date?
        ) {
            self.id = id
            self.taskID = taskID
            self.kind = kind
            self.offsetMinutes = offsetMinutes
            self.fireDate = fireDate
            self.lastFiredAt = lastFiredAt
            self.snoozedUntil = snoozedUntil
            self.createdAt = createdAt
        }
    }

    public struct SpecDraft: Sendable {
        public var kind: NotificationKind
        public var offsetMinutes: Int32?
        public var fireDate: Date?
        public var snoozedUntil: Date?
    }

    @discardableResult
    public func add(
        taskID: UUID,
        kind: NotificationKind,
        offsetMinutes: Int32?,
        fireDate: Date?
    ) async throws -> UUID {
        try await context.perform { [self] in
            let task = try fetchTask(id: taskID, in: context)
            // Default specs are singletons per (task, kind): exactly one
            // .defaultStart and one .defaultDeadline may exist for a task.
            // Two overlapping reconcile cycles (or two devices) can each try
            // to materialize the default; without this guard they'd create a
            // duplicate that the scheduler would then de-dup at the OS level
            // only by accident. Returning the existing id keeps `add`
            // idempotent for defaults while leaving offset/nudge multi-instance
            // (review notif-2). The dedup is scoped to this task's specs via the
            // `task == %@` predicate, not a model-level unique constraint, so it
            // composes with CloudKit (which doesn't honor uniqueness constraints).
            if kind == .defaultStart || kind == .defaultDeadline {
                let existing = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
                existing.predicate = NSPredicate(format: "task == %@ AND kindRaw == %d", task, kind.rawValue)
                existing.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                let found = try context.fetch(existing)
                if let survivor = found.first {
                    // Collapse any duplicates a previous race already created so
                    // the store self-heals on the next add (CloudKit imports
                    // can deliver a second default before this guard ran).
                    for dup in found.dropFirst() {
                        context.delete(dup)
                    }
                    if context.hasChanges { try context.save() }
                    return survivor.id ?? UUID()
                }
            }
            let spec = NotificationSpec(context: context)
            let id = UUID()
            spec.id = id
            spec.task = task
            spec.kind = kind
            if let offsetMinutes {
                spec.offsetMinutes = NSNumber(value: offsetMinutes)
            } else {
                spec.offsetMinutes = nil
            }
            spec.fireDate = fireDate
            spec.createdAt = Date()
            try context.save()
            return id
        }
    }

    public func fetch(id: UUID) async throws -> SpecRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return Self.record(from: m)
        }
    }

    public func specs(forTask taskID: UUID) async throws -> [SpecRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    public func update(id: UUID, _ block: @escaping @Sendable (inout SpecDraft) -> Void) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            var draft = SpecDraft(
                kind: m.kind,
                offsetMinutes: m.offsetMinutes?.int32Value,
                fireDate: m.fireDate,
                snoozedUntil: m.snoozedUntil
            )
            block(&draft)
            m.kind = draft.kind
            if let offset = draft.offsetMinutes {
                m.offsetMinutes = NSNumber(value: offset)
            } else {
                m.offsetMinutes = nil
            }
            m.fireDate = draft.fireDate
            m.snoozedUntil = draft.snoozedUntil
            try context.save()
        }
    }

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    public func recordLastFired(id: UUID, at date: Date) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.lastFiredAt = date
            try context.save()
        }
    }

    // MARK: - Helpers

    private func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> NotificationSpec {
        let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
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

    static func record(from m: NotificationSpec) -> SpecRecord {
        SpecRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            kind: m.kind,
            offsetMinutes: m.offsetMinutes?.int32Value,
            fireDate: m.fireDate,
            lastFiredAt: m.lastFiredAt,
            snoozedUntil: m.snoozedUntil,
            createdAt: m.createdAt
        )
    }
}
