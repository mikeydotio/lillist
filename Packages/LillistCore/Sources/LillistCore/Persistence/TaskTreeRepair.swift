import Foundation
import CoreData

/// The "sever this node's parent link, promoting it to root" mutation —
/// one concrete action independent call sites in the data-sync-hardening
/// program all perform for the same underlying reason: a node has been
/// separated from an ancestor that's going away (or was never valid) and
/// must survive on its own rather than carry a dangling or illegal parent
/// reference. Used by `CascadeReaper`'s purge-time barrier (`C1`, via
/// `TaskStore.batchPurge` and `AutoPurgeJob`) and `TreeIntegrityChecker`'s
/// launch-time self-heal (`H7`). `TaskStore.restore`'s inline equivalent
/// (`C2`) predates this type and is left as-is.
enum TaskTreeRepair {
    static func promoteToRoot(_ task: LillistTask, at now: Date = Date()) {
        task.parent = nil
        task.modifiedAt = now
        task.stampCurrentSchemaVersion()
    }
}
