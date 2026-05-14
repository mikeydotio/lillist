import Foundation
import CoreData

@objc(AppPreferences)
public final class AppPreferences: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var defaultAllDayNotificationHour: Int16
    @NSManaged public var defaultAllDayNotificationMinute: Int16
    @NSManaged public var morningSummaryEnabled: Bool
    @NSManaged public var morningSummaryHour: Int16
    @NSManaged public var morningSummaryMinute: Int16
    @NSManaged public var trashRetentionDays: Int16
    @NSManaged public var defaultTaskListSortRaw: String?
    @NSManaged public var crashPromptsEnabled: Bool
}

extension AppPreferences {
    public var defaultTaskListSort: SortField {
        get { SortField(rawValue: defaultTaskListSortRaw ?? "manualPosition") ?? .manualPosition }
        set { defaultTaskListSortRaw = newValue.rawValue }
    }
}
