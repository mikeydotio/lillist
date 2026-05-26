import Foundation
import CoreData

@objc(LillistTask)
public final class LillistTask: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var notes: String?
    @NSManaged public var statusRaw: Int16
    @NSManaged public var start: Date?
    @NSManaged public var startHasTime: Bool
    @NSManaged public var deadline: Date?
    @NSManaged public var deadlineHasTime: Bool
    @NSManaged public var position: Double
    @NSManaged public var isPinned: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var closedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var deletedAt: Date?

    @NSManaged public var parent: LillistTask?
    @NSManaged public var children: NSSet?
    @NSManaged public var tags: NSSet?
    @NSManaged public var journalEntries: NSSet?
    @NSManaged public var attachments: NSSet?
    @NSManaged public var series: Series?
    @NSManaged public var seriesAsSeed: Series?
    @NSManaged public var notificationSpecs: NSSet?
}

extension LillistTask {
    @objc(addChildrenObject:)
    @NSManaged public func addToChildren(_ value: LillistTask)

    @objc(removeChildrenObject:)
    @NSManaged public func removeFromChildren(_ value: LillistTask)

    @objc(addChildren:)
    @NSManaged public func addToChildren(_ values: NSSet)

    @objc(removeChildren:)
    @NSManaged public func removeFromChildren(_ values: NSSet)

    @objc(addTagsObject:)
    @NSManaged public func addToTags(_ value: Tag)

    @objc(removeTagsObject:)
    @NSManaged public func removeFromTags(_ value: Tag)

    @objc(addTags:)
    @NSManaged public func addToTags(_ values: NSSet)

    @objc(removeTags:)
    @NSManaged public func removeFromTags(_ values: NSSet)

    @objc(addJournalEntriesObject:)
    @NSManaged public func addToJournalEntries(_ value: JournalEntry)

    @objc(removeJournalEntriesObject:)
    @NSManaged public func removeFromJournalEntries(_ value: JournalEntry)

    @objc(addAttachmentsObject:)
    @NSManaged public func addToAttachments(_ value: Attachment)

    @objc(removeAttachmentsObject:)
    @NSManaged public func removeFromAttachments(_ value: Attachment)

    @objc(addNotificationSpecsObject:)
    @NSManaged public func addToNotificationSpecs(_ value: NotificationSpec)

    @objc(removeNotificationSpecsObject:)
    @NSManaged public func removeFromNotificationSpecs(_ value: NotificationSpec)

    @objc(addNotificationSpecs:)
    @NSManaged public func addToNotificationSpecs(_ values: NSSet)

    @objc(removeNotificationSpecs:)
    @NSManaged public func removeFromNotificationSpecs(_ values: NSSet)
}

extension LillistTask {
    /// Typed accessor over `statusRaw`.
    public var status: Status {
        get { Status(rawValue: Int(statusRaw)) ?? .todo }
        set { statusRaw = Int16(newValue.rawValue) }
    }
}
