import Foundation
import CoreData

@objc(JournalEntry)
public final class JournalEntry: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var kindRaw: Int16
    @NSManaged public var body: String?
    @NSManaged public var payload: Data?
    @NSManaged public var createdAt: Date?
    @NSManaged public var editedAt: Date?

    @NSManaged public var task: LillistTask?
    @NSManaged public var attachments: NSSet?
}

extension JournalEntry {
    @objc(addAttachmentsObject:)
    @NSManaged public func addToAttachments(_ value: Attachment)

    @objc(removeAttachmentsObject:)
    @NSManaged public func removeFromAttachments(_ value: Attachment)
}

extension JournalEntry {
    public var kind: JournalEntryKind {
        get { JournalEntryKind(rawValue: Int(kindRaw)) ?? .note }
        set { kindRaw = Int16(newValue.rawValue) }
    }
}
