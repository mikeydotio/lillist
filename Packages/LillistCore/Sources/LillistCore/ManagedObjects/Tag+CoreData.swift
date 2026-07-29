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
        descendants(visited: [])
    }

    /// H7: same shape as `LillistTask`'s ancestor/descendant walks — a
    /// CloudKit merge can create a parent-cycle in the Tag hierarchy too,
    /// and this walk never mutates anything as it descends, so it is not
    /// self-limiting. `visited` tracks the path from the original root to
    /// the current node (extended per call, not shared across sibling
    /// branches — the to-one `parent` relationship means two different
    /// legitimate branches can never reconverge on the same node, so a cycle
    /// can only be re-encountered along the single path that contains it).
    private func descendants(visited: Set<NSManagedObjectID>) -> [Tag] {
        guard let children = self.children as? Set<Tag> else { return [] }
        var visited = visited
        visited.insert(self.objectID)
        var out: [Tag] = []
        for child in children where !visited.contains(child.objectID) {
            out.append(child)
            out.append(contentsOf: child.descendants(visited: visited))
        }
        return out
    }
}
