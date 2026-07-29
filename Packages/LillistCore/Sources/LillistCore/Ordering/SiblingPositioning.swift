import Foundation
import CoreData

/// Live-fetch computation of where a new (or spawned) `LillistTask` lands
/// among its siblings — the shared core `TaskStore.nextPositionDetail` and
/// `RecurrenceSpawner.spawnIfNeeded` both delegate to.
///
/// H1: `RecurrenceSpawner` used to anchor a spawned instance's position at
/// `series.seedTask.position + 0.5` — a value that never changes across a
/// series' lifetime, so every spawn after the first collided at the
/// identical fractional position. Placement must instead be computed
/// against the *live* sibling set at spawn time, exactly like any other
/// task creation — this type is the single source of truth for that
/// computation so `TaskStore` and `RecurrenceSpawner` can't drift apart.
enum SiblingPositioning {
    /// The position a new row should take among `parent`'s live (non-trashed)
    /// siblings, plus the observed edge sibling position for diagnostics.
    ///
    /// `placement` selects which end the new row lands at:
    /// - `.bottom` (default): the edge is the *max* sibling position and the
    ///   row is placed after it (`edge + 1.0`).
    /// - `.top`: the edge is the *min* sibling position and the row is placed
    ///   before it (`edge - 1.0`).
    /// An empty sibling group yields `1.0` either way.
    static func nextPositionDetail(
        forParent parent: LillistTask?,
        placement: NewTaskPlacement = .bottom,
        in context: NSManagedObjectContext
    ) throws -> (assigned: Double, observedMax: Double?) {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        // H4: ignore trashed siblings when computing the edge — a trashed
        // sibling is logically absent from the ordering domain everywhere
        // else in this file.
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
        }
        // For `.bottom` we need the largest position (sort desc); for `.top`
        // the smallest (sort asc). Either way we fetch a single edge row.
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: placement == .top)]
        req.fetchLimit = 1
        let edgePosition = try context.fetch(req).first?.position
        switch placement {
        case .bottom:
            return (FractionalPosition.position(after: edgePosition, before: nil), edgePosition)
        case .top:
            return (FractionalPosition.position(after: nil, before: edgePosition), edgePosition)
        }
    }
}
