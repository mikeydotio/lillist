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
        /// Device-local snooze, hydrated from ``SnoozeStateStore`` — **not**
        /// from Core Data (`LIL-90`). Always `nil` as projected by this store;
        /// the scheduler fills it in before computing a fire date.
        public var snoozedUntil: Date?
        /// IANA zone captured at scheduling time; `nil` for pre-`LIL-83` rows.
        public var scheduledTimeZoneID: String?
        public var createdAt: Date?

        public init(
            id: UUID,
            taskID: UUID,
            kind: NotificationKind,
            offsetMinutes: Int32?,
            fireDate: Date?,
            lastFiredAt: Date?,
            snoozedUntil: Date?,
            scheduledTimeZoneID: String? = nil,
            createdAt: Date?
        ) {
            self.id = id
            self.taskID = taskID
            self.kind = kind
            self.offsetMinutes = offsetMinutes
            self.fireDate = fireDate
            self.lastFiredAt = lastFiredAt
            self.snoozedUntil = snoozedUntil
            self.scheduledTimeZoneID = scheduledTimeZoneID
            self.createdAt = createdAt
        }
    }

    public struct SpecDraft: Sendable {
        public var kind: NotificationKind
        public var offsetMinutes: Int32?
        public var fireDate: Date?
        /// - Warning: **Deprecated (`LIL-90`)** and ignored by ``update(id:_:)``.
        ///   Snooze is device-local; write it through ``SnoozeStateStore``.
        ///   Kept on the draft only so existing callers still compile.
        public var snoozedUntil: Date?
        /// Set to re-anchor this reminder to a different zone (`LIL-83`).
        public var scheduledTimeZoneID: String?
    }

    @discardableResult
    /// - Parameter scheduledTimeZoneID: IANA zone to anchor this reminder to
    ///   (`LIL-83`). Callers pass the zone the user is in *now*; `nil` leaves
    ///   the reminder legacy-resolved through each device's current zone.
    public func add(
        taskID: UUID,
        kind: NotificationKind,
        offsetMinutes: Int32?,
        fireDate: Date?,
        scheduledTimeZoneID: String? = nil
    ) async throws -> UUID {
        try await withMutationRollback(context: context) { [self] in
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
                    // X19: no manual `if hasChanges { save() }` here — that
                    // duplicated withMutationRollback's own save-only-if-
                    // dirtied gate with no added safety (both read the same
                    // context-wide flag), while looking like a per-branch
                    // check. The common no-duplicates-found case now makes
                    // zero changes and the helper triggers zero saves for
                    // it — verified via a did-save-notification assertion
                    // in NotificationSpecStoreX19Tests, not just inferred.
                    for dup in found.dropFirst() {
                        context.delete(dup)
                    }
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
            spec.scheduledTimeZoneID = scheduledTimeZoneID
            spec.createdAt = Date()
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
        try await withMutationRollback(context: context) { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            var draft = SpecDraft(
                kind: m.kind,
                offsetMinutes: m.offsetMinutes?.int32Value,
                fireDate: m.fireDate,
                snoozedUntil: nil,
                scheduledTimeZoneID: m.scheduledTimeZoneID
            )
            block(&draft)
            m.kind = draft.kind
            if let offset = draft.offsetMinutes {
                m.offsetMinutes = NSNumber(value: offset)
            } else {
                m.offsetMinutes = nil
            }
            m.fireDate = draft.fireDate
            m.scheduledTimeZoneID = draft.scheduledTimeZoneID
            // `draft.snoozedUntil` is deliberately NOT written back (`LIL-90`).
            // Snooze is device-local; a synced snooze is what made a remote
            // in-place spec edit reachable in the first place.
        }
    }

    public func delete(id: UUID) async throws {
        try await withMutationRollback(context: context) { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
        }
    }

    public func recordLastFired(id: UUID, at date: Date) async throws {
        try await withMutationRollback(context: context) { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.lastFiredAt = date
        }
    }

    /// X9: batch existence check — returns the subset of `ids` that still
    /// have a live `NotificationSpec` row. One fetch regardless of `ids`
    /// count, so `NotificationScheduler.reconcileOrphanedPendingRequests()`
    /// costs one round trip per sweep, not N per-id lookups.
    public func existingIDs(among ids: [UUID]) async throws -> Set<UUID> {
        guard ids.isEmpty == false else { return [] }
        return try await context.perform { [self] in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id IN %@", ids)
            return try Set(context.fetch(req).compactMap(\.id))
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

    /// - Note: `snoozedUntil` is projected as `nil`, never from the Core Data
    ///   column (`LIL-90`). Snooze is device-local; the scheduler hydrates it
    ///   from ``SnoozeStateStore``. Reading the column here would resurrect the
    ///   synced-snooze behaviour this change exists to remove.
    static func record(from m: NotificationSpec) -> SpecRecord {
        SpecRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            kind: m.kind,
            offsetMinutes: m.offsetMinutes?.int32Value,
            fireDate: m.fireDate,
            lastFiredAt: m.lastFiredAt,
            snoozedUntil: nil,
            scheduledTimeZoneID: m.scheduledTimeZoneID,
            createdAt: m.createdAt
        )
    }
}
