import Foundation
import CoreData

public final class PreferencesStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct Prefs: Sendable, Equatable {
        public var defaultAllDayHour: Int16
        public var defaultAllDayMinute: Int16
        public var morningSummaryEnabled: Bool
        public var morningSummaryHour: Int16
        public var morningSummaryMinute: Int16
        public var trashRetentionDays: Int16
        public var defaultTaskListSort: SortField
    }

    public func read() async throws -> Prefs {
        try await context.perform { [self] in
            let row = try fetchOrCreateSingleton(in: context)
            return Prefs(
                defaultAllDayHour: row.defaultAllDayNotificationHour,
                defaultAllDayMinute: row.defaultAllDayNotificationMinute,
                morningSummaryEnabled: row.morningSummaryEnabled,
                morningSummaryHour: row.morningSummaryHour,
                morningSummaryMinute: row.morningSummaryMinute,
                trashRetentionDays: row.trashRetentionDays,
                defaultTaskListSort: row.defaultTaskListSort
            )
        }
    }

    public func update(_ block: @escaping (inout Prefs) -> Void) async throws {
        try await context.perform { [self] in
            let row = try fetchOrCreateSingleton(in: context)
            var prefs = Prefs(
                defaultAllDayHour: row.defaultAllDayNotificationHour,
                defaultAllDayMinute: row.defaultAllDayNotificationMinute,
                morningSummaryEnabled: row.morningSummaryEnabled,
                morningSummaryHour: row.morningSummaryHour,
                morningSummaryMinute: row.morningSummaryMinute,
                trashRetentionDays: row.trashRetentionDays,
                defaultTaskListSort: row.defaultTaskListSort
            )
            block(&prefs)
            row.defaultAllDayNotificationHour = prefs.defaultAllDayHour
            row.defaultAllDayNotificationMinute = prefs.defaultAllDayMinute
            row.morningSummaryEnabled = prefs.morningSummaryEnabled
            row.morningSummaryHour = prefs.morningSummaryHour
            row.morningSummaryMinute = prefs.morningSummaryMinute
            row.trashRetentionDays = prefs.trashRetentionDays
            row.defaultTaskListSort = prefs.defaultTaskListSort
            try context.save()
        }
    }

    /// Test helper: count of AppPreferences rows. Asserts singleton invariant.
    public func rowCount() async throws -> Int {
        try await context.perform { [self] in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            return try context.count(for: req)
        }
    }

    private func fetchOrCreateSingleton(in ctx: NSManagedObjectContext) throws -> AppPreferences {
        let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        req.fetchLimit = 1
        if let existing = try ctx.fetch(req).first {
            return existing
        }
        let row = AppPreferences(context: ctx)
        row.id = UUID()
        row.defaultAllDayNotificationHour = 9
        row.defaultAllDayNotificationMinute = 0
        row.morningSummaryEnabled = true
        row.morningSummaryHour = 9
        row.morningSummaryMinute = 0
        row.trashRetentionDays = 30
        row.defaultTaskListSortRaw = SortField.manualPosition.rawValue
        try ctx.save()
        return row
    }
}
