import Foundation
import CoreData

@objc(Tag)
public final class Tag: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var tintColor: String?
    @NSManaged public var position: Double

    @NSManaged public var parent: Tag?
    @NSManaged public var children: NSSet?
    @NSManaged public var tasks: NSSet?
}

extension Tag {
    @objc(addChildrenObject:)
    @NSManaged public func addToChildren(_ value: Tag)

    @objc(removeChildrenObject:)
    @NSManaged public func removeFromChildren(_ value: Tag)

    @objc(addTasksObject:)
    @NSManaged public func addToTasks(_ value: LillistTask)

    @objc(removeTasksObject:)
    @NSManaged public func removeFromTasks(_ value: LillistTask)
}

extension Tag {
    /// Returns the root ancestor of this tag (self if root).
    public var root: Tag {
        var current = self
        while let p = current.parent {
            current = p
        }
        return current
    }

    /// All descendant tags (depth-first, not including self).
    public var descendants: [Tag] {
        guard let children = self.children as? Set<Tag> else { return [] }
        var out: [Tag] = []
        for child in children {
            out.append(child)
            out.append(contentsOf: child.descendants)
        }
        return out
    }
}
