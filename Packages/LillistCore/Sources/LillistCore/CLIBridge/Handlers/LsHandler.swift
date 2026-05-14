import Foundation
import CoreData

extension CLIBridge {
    public enum LsHandler {
        /// Returns task records matching the given flags/saved filter, sorted.
        public static func run(
            flags: FilterFlags,
            savedFilterName: String?,
            sort: SortField,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar
        ) async throws -> [TaskStore.TaskRecord] {
            let group: PredicateGroup
            if let name = savedFilterName {
                let saved = try await SmartFilterStore(persistence: persistence).fetch(byName: name)
                group = saved.group
            } else {
                group = try await flags.toPredicateGroup(persistence: persistence, now: now, calendar: calendar)
            }

            let predicate = NSPredicateCompiler.compile(group, now: now, calendar: calendar)
            let ctx = persistence.container.viewContext
            let matched: [TaskStore.TaskRecord] = try await ctx.perform {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = predicate
                let mos = try ctx.fetch(req)
                return mos.map { Self.record(from: $0) }
            }
            return Self.sort(matched, by: sort)
        }

        /// Helper that returns every task record (optionally including trash).
        /// Reused by EvalHandler.
        public static func fetchAllNonTrashedRecords(
            persistence: PersistenceController,
            includeTrash: Bool
        ) async throws -> [TaskStore.TaskRecord] {
            let ctx = persistence.container.viewContext
            return try await ctx.perform {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                if includeTrash == false {
                    req.predicate = NSPredicate(format: "deletedAt == nil")
                }
                return try ctx.fetch(req).map { Self.record(from: $0) }
            }
        }

        static func record(from m: LillistTask) -> TaskStore.TaskRecord {
            TaskStore.TaskRecord(
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

        static func sort(_ records: [TaskStore.TaskRecord], by field: SortField) -> [TaskStore.TaskRecord] {
            switch field {
            case .title: return records.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            case .start: return records.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            case .deadline: return records.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            case .createdAt: return records.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            case .modifiedAt: return records.sorted { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }
            case .closedAt: return records.sorted { ($0.closedAt ?? .distantFuture) < ($1.closedAt ?? .distantFuture) }
            case .status: return records.sorted { $0.status.rawValue < $1.status.rawValue }
            case .manualPosition: return records.sorted { $0.position < $1.position }
            }
        }
    }
}
