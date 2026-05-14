import Foundation
import CoreData

@objc(NotificationSpec)
public final class NotificationSpec: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var kindRaw: Int16
    @NSManaged public var offsetMinutes: NSNumber?
    @NSManaged public var fireDate: Date?
    @NSManaged public var lastFiredAt: Date?
    @NSManaged public var snoozedUntil: Date?
    @NSManaged public var createdAt: Date?

    @NSManaged public var task: LillistTask?
}

extension NotificationSpec {
    /// Typed accessor over `kindRaw`.
    public var kind: NotificationKind {
        get { NotificationKind(rawValue: Int(kindRaw)) ?? .defaultStart }
        set { kindRaw = Int16(newValue.rawValue) }
    }
}
