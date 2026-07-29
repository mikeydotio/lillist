import Foundation
import CoreData

enum Validators {
    /// Walks up from `proposedParent` (and its ancestors) looking for `candidate`.
    /// Returns true if assigning `candidate` as a descendant of `proposedParent`
    /// would create a cycle.
    ///
    /// H7: a CloudKit property-level merge can create a parent-cycle no local
    /// mutation path could (`X.parent == Y`, `Y.parent == X`, or longer). This
    /// walk can encounter such a *pre-existing* cycle upstream of `newParent`
    /// that has nothing to do with `candidate` — without a visited-set guard
    /// it would spin on that cycle forever instead of ever reaching
    /// `candidate` (or running off the end). A revisit is treated
    /// conservatively as "would create a cycle": the walk cannot prove the
    /// assignment is safe, so it blocks rather than loops.
    static func wouldCreateCycle(candidate: LillistTask, newParent: LillistTask?) -> Bool {
        guard let newParent else { return false }
        if candidate.objectID == newParent.objectID { return true }
        var visited: Set<NSManagedObjectID> = [newParent.objectID]
        var cursor: LillistTask? = newParent.parent
        while let node = cursor {
            if node.objectID == candidate.objectID { return true }
            guard visited.insert(node.objectID).inserted else { return true }
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
