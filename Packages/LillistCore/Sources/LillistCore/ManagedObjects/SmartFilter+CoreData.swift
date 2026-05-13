import Foundation
import CoreData

@objc(SmartFilter)
public final class SmartFilter: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var predicateGroupJSON: String?
    @NSManaged public var tintColor: String?
    @NSManaged public var sortFieldRaw: String?
    @NSManaged public var sortAscending: Bool
    @NSManaged public var isPinned: Bool
    @NSManaged public var position: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
}

extension SmartFilter {
    /// Typed accessor over `sortFieldRaw`. Defaults to `.deadline` when the
    /// stored raw value is missing or unknown.
    public var sortField: SortField {
        get { SortField(rawValue: sortFieldRaw ?? "deadline") ?? .deadline }
        set { sortFieldRaw = newValue.rawValue }
    }
}
