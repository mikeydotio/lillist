import Foundation
import CoreData

@objc(Attachment)
public final class Attachment: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var kindRaw: Int16
    @NSManaged public var filename: String?
    @NSManaged public var uti: String?
    @NSManaged public var byteSize: Int64
    @NSManaged public var data: Data?
    @NSManaged public var linkPreviewJSON: String?
    @NSManaged public var createdAt: Date?

    @NSManaged public var task: LillistTask?
    @NSManaged public var journalEntry: JournalEntry?
}

extension Attachment {
    public var kind: AttachmentKind {
        get { AttachmentKind(rawValue: Int(kindRaw)) ?? .file }
        set { kindRaw = Int16(newValue.rawValue) }
    }
}
