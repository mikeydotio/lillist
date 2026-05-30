import Foundation
import CoreData

/// Spawns the next instance of a `Series` when an existing instance closes.
///
/// Invoked from inside `TaskStore.transition` while the `viewContext` is
/// already locked — so this code runs synchronously on the context queue
/// and shares the same save. Calling this with a non-series task is a no-op.
///
/// Re-opening a closed task does NOT call this — that's a one-way operation
/// per design Section 8.
enum RecurrenceSpawner {
    /// If `closed` is an instance of a still-spawning series, create the
    /// next instance and update the series' `nextOccurrenceAfter`. No-op
    /// when there's no series or the series has reached its limit.
    ///
    /// Pre: called inside `context.perform { … }`. Caller is responsible
    /// for `context.save()` afterward.
    ///
    /// - Returns: The spawned task's `UUID` if a new instance was created,
    ///   or `nil` otherwise. Plan 5 callers use this to reconcile
    ///   notifications for the spawn after save.
    @discardableResult
    static func spawnIfNeeded(
        forClosedTask closed: LillistTask,
        in context: NSManagedObjectContext
    ) -> UUID? {
        guard let series = closed.series else { return nil }
        guard let rule = series.rule else { return nil }
        guard let nextDate = series.nextOccurrenceAfter else { return nil }

        let seed = series.seedTask ?? closed
        let spawn = LillistTask(context: context)
        let spawnID = UUID()
        spawn.id = spawnID
        spawn.title = seed.title
        spawn.notes = seed.notes
        spawn.statusRaw = Int16(Status.todo.rawValue)
        spawn.startHasTime = seed.startHasTime
        spawn.deadlineHasTime = seed.deadlineHasTime
        spawn.isPinned = false
        spawn.createdAt = Date()
        spawn.modifiedAt = spawn.createdAt
        spawn.parent = seed.parent
        spawn.position = seed.position + 0.5
        spawn.series = series
        spawn.tags = seed.tags

        if let seedStart = seed.start {
            let delta = nextDate.timeIntervalSince(seedStart)
            spawn.start = nextDate
            spawn.deadline = seed.deadline.map { $0.addingTimeInterval(delta) }
        } else {
            spawn.start = nextDate
            spawn.deadline = seed.deadline
        }

        if let kids = seed.children as? Set<LillistTask> {
            for kid in kids where kid.deletedAt == nil {
                deepCopy(kid, into: spawn, in: context)
            }
        }

        let advanced = advance(rule: rule, lastOccurrence: nextDate, completedAt: closed.closedAt ?? Date())
        let countLimited = countReached(series: series, rule: rule)
        series.nextOccurrenceAfter = countLimited ? nil : advanced
        return spawnID
    }

    private static func deepCopy(
        _ source: LillistTask,
        into newParent: LillistTask,
        in context: NSManagedObjectContext
    ) {
        let copy = LillistTask(context: context)
        copy.id = UUID()
        copy.title = source.title
        copy.notes = source.notes
        copy.statusRaw = Int16(Status.todo.rawValue)
        copy.start = source.start
        copy.startHasTime = source.startHasTime
        copy.deadline = source.deadline
        copy.deadlineHasTime = source.deadlineHasTime
        copy.isPinned = source.isPinned
        copy.createdAt = Date()
        copy.modifiedAt = copy.createdAt
        copy.position = source.position
        copy.parent = newParent
        copy.tags = source.tags

        if let kids = source.children as? Set<LillistTask> {
            for kid in kids where kid.deletedAt == nil {
                deepCopy(kid, into: copy, in: context)
            }
        }
    }

    private static func advance(
        rule: RecurrenceRule,
        lastOccurrence: Date,
        completedAt: Date
    ) -> Date? {
        switch rule {
        case .calendar(let cal):
            return RecurrenceExpander.nextOccurrences(
                after: lastOccurrence,
                rule: cal,
                calendar: Calendar.current,
                count: 1
            ).first
        case .afterCompletion(let after):
            return RecurrenceExpander.nextAfterCompletion(completedAt: completedAt, rule: after)
        }
    }

    /// True if the rule's `count` budget would be consumed after this spawn.
    /// The seed is instance #1; each spawned instance counts toward `count`.
    /// Soft-deleted (trashed) instances are excluded so trashing an instance
    /// of a `count = N` series doesn't permanently stall the series one short
    /// of its budget (stores-7).
    private static func countReached(
        series: Series,
        rule: RecurrenceRule
    ) -> Bool {
        guard case .calendar(let cal) = rule, let count = cal.count else { return false }
        let instances = (series.instances as? Set<LillistTask>) ?? []
        let live = instances.filter { $0.deletedAt == nil }.count
        // `live` already includes the new spawn (we set spawn.series = series above).
        return live >= count
    }
}
