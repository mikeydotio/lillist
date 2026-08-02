import Foundation
import CoreData

@objc(NotificationSpec)
public final class NotificationSpec: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var kindRaw: Int16
    @NSManaged public var offsetMinutes: NSNumber?
    @NSManaged public var fireDate: Date?
    @NSManaged public var lastFiredAt: Date?
    /// - Warning: **Deprecated (`LIL-90`).** Snooze state is device-local and
    ///   lives in ``SnoozeStateStore``. This column is read exactly once, by
    ///   ``SnoozeStatePartitionMigrator``, and never written again. It cannot be
    ///   removed: CloudKit has no way to delete a field from a deployed schema.
    @NSManaged public var snoozedUntil: Date?
    /// IANA identifier (e.g. `"America/New_York"`) of the zone the user was in
    /// when this reminder was scheduled — `LIL-83`.
    ///
    /// Travels with the reminder so every device resolves the same absolute
    /// instant, which is what lets the `lastFiredAt` dedup guard work across
    /// zones. `nil` means a pre-`LIL-83` reminder: resolve it through the
    /// device's current zone, exactly as before.
    @NSManaged public var scheduledTimeZoneID: String?
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
