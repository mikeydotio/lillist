import Foundation
import CoreData

public final class SeriesStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// Value-type DTO for `Series`.
    public struct SeriesRecord: Sendable, Equatable {
        public var id: UUID
        public var seedTaskID: UUID?
        public var rule: RecurrenceRule?
        public var nextOccurrenceAfter: Date?
    }

    // MARK: - Create

    @discardableResult
    public func create(fromSeedTask seedTaskID: UUID, rule: RecurrenceRule) async throws -> UUID {
        try await context.perform { [self] in
            let task = try TaskStore(persistence: persistence).fetchManagedObject(id: seedTaskID, in: context)
            let series = Series(context: context)
            series.id = UUID()
            series.rule = rule
            series.seedTask = task
            // Membership: the seed is also part of `instances`.
            task.series = series

            let anchor = task.start ?? task.createdAt ?? Date()
            series.nextOccurrenceAfter = Self.computeNextOccurrence(rule: rule, after: anchor)

            try context.save()
            return series.id!
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> SeriesRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return record(from: m)
        }
    }

    public func instances(of seriesID: UUID) async throws -> [UUID] {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: seriesID, in: context)
            guard let set = m.instances as? Set<LillistTask> else { return [] }
            return set.compactMap { $0.id }
        }
    }

    public func list() async throws -> [SeriesRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<Series>(entityName: "Series")
            req.sortDescriptors = [NSSortDescriptor(key: "nextOccurrenceAfter", ascending: true)]
            return try context.fetch(req).map(record(from:))
        }
    }

    // MARK: - Update

    public func update(id: UUID, rule: RecurrenceRule) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.rule = rule
            let anchor = m.seedTask?.start ?? m.seedTask?.createdAt ?? Date()
            m.nextOccurrenceAfter = Self.computeNextOccurrence(rule: rule, after: anchor)
            try context.save()
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Fork (edit-all-future)

    /// Create a new `Series` rooted at `instanceID`, leaving the old series
    /// and its existing instances unchanged. Subsequent spawns of the
    /// **forked** instance will come from the new series.
    @discardableResult
    public func forkFutureFromInstance(instanceID: UUID) async throws -> UUID {
        try await context.perform { [self] in
            let task = try TaskStore(persistence: persistence).fetchManagedObject(id: instanceID, in: context)
            guard let oldSeries = task.series else {
                throw LillistError.validationFailed([
                    .init(field: "instance", message: "task is not part of a series")
                ])
            }
            if let seed = oldSeries.seedTask, seed.objectID == task.objectID {
                throw LillistError.validationFailed([
                    .init(field: "instance", message: "cannot fork from the seed task")
                ])
            }
            guard let rule = oldSeries.rule else {
                throw LillistError.validationFailed([
                    .init(field: "series", message: "missing rule")
                ])
            }

            let newSeries = Series(context: context)
            newSeries.id = UUID()
            newSeries.rule = rule
            newSeries.seedTask = task
            task.series = newSeries
            let anchor = task.start ?? task.createdAt ?? Date()
            newSeries.nextOccurrenceAfter = Self.computeNextOccurrence(rule: rule, after: anchor)

            try context.save()
            return newSeries.id!
        }
    }

    // MARK: - Internal helpers (used by RecurrenceSpawner)

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> Series {
        let req = NSFetchRequest<Series>(entityName: "Series")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else {
            throw LillistError.notFound
        }
        return m
    }

    static func computeNextOccurrence(rule: RecurrenceRule, after anchor: Date) -> Date? {
        switch rule {
        case .calendar(let cal):
            return RecurrenceExpander.nextOccurrences(
                after: anchor,
                rule: cal,
                calendar: Calendar.current,
                count: 1
            ).first
        case .afterCompletion(let after):
            return RecurrenceExpander.nextAfterCompletion(completedAt: anchor, rule: after)
        }
    }

    func record(from m: Series) -> SeriesRecord {
        SeriesRecord(
            id: m.id ?? UUID(),
            seedTaskID: m.seedTask?.id,
            rule: m.rule,
            nextOccurrenceAfter: m.nextOccurrenceAfter
        )
    }
}
