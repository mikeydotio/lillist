import Foundation
import CoreData

enum Validators {
    /// Walks up from `proposedParent` (and its ancestors) looking for `candidate`.
    /// Returns true if assigning `candidate` as a descendant of `proposedParent`
    /// would create a cycle.
    static func wouldCreateCycle(candidate: LillistTask, newParent: LillistTask?) -> Bool {
        guard let newParent else { return false }
        if candidate.objectID == newParent.objectID { return true }
        var cursor: LillistTask? = newParent.parent
        while let node = cursor {
            if node.objectID == candidate.objectID { return true }
            cursor = node.parent
        }
        return false
    }

    /// Returns a non-colliding name by appending " (2)", " (3)", … as needed.
    static func uniqueName(desired: String, existing: Set<String>) -> String {
        guard existing.contains(desired) else { return desired }
        var n = 2
        while existing.contains("\(desired) (\(n))") { n += 1 }
        return "\(desired) (\(n))"
    }
}
