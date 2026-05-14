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
        /// Whether the post-crash report sheet is shown on the next
        /// launch after a crash. Default `true`; see design Section 8.
        public var crashPromptsEnabled: Bool
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
                defaultTaskListSort: row.defaultTaskListSort,
                crashPromptsEnabled: row.crashPromptsEnabled
            )
        }
    }

    public func update(_ block: @escaping @Sendable (inout Prefs) -> Void) async throws {
        try await context.perform { [self] in
            let row = try fetchOrCreateSingleton(in: context)
            var prefs = Prefs(
                defaultAllDayHour: row.defaultAllDayNotificationHour,
                defaultAllDayMinute: row.defaultAllDayNotificationMinute,
                morningSummaryEnabled: row.morningSummaryEnabled,
                morningSummaryHour: row.morningSummaryHour,
                morningSummaryMinute: row.morningSummaryMinute,
                trashRetentionDays: row.trashRetentionDays,
                defaultTaskListSort: row.defaultTaskListSort,
                crashPromptsEnabled: row.crashPromptsEnabled
            )
            block(&prefs)
            row.defaultAllDayNotificationHour = prefs.defaultAllDayHour
            row.defaultAllDayNotificationMinute = prefs.defaultAllDayMinute
            row.morningSummaryEnabled = prefs.morningSummaryEnabled
            row.morningSummaryHour = prefs.morningSummaryHour
            row.morningSummaryMinute = prefs.morningSummaryMinute
            row.trashRetentionDays = prefs.trashRetentionDays
            row.defaultTaskListSort = prefs.defaultTaskListSort
            row.crashPromptsEnabled = prefs.crashPromptsEnabled
            try context.save()
        }
    }

    /// Convenience: toggle whether the post-crash report sheet is
    /// presented on next launch.
    public func setCrashPromptsEnabled(_ value: Bool) async throws {
        try await update { $0.crashPromptsEnabled = value }
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
        row.crashPromptsEnabled = true
        try ctx.save()
        return row
    }
}
