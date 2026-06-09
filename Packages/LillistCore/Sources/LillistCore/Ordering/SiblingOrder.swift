import Foundation

/// Canonical personalized sibling order: position ascending, then
/// id.uuidString ascending on ties. The single source of truth shared
/// by every presenter (iOS TaskTree, macOS buildTree) and every
/// recompaction.
///
/// Never use NSSortDescriptor on the UUID `id` attribute — Core Data
/// orders UUIDs as raw bytes, which is NOT guaranteed to equal Swift's
/// uuidString lexical order. Always sort in Swift in-memory.
public enum SiblingOrder {
    public static func precedes(
        positionA: Double, idA: UUID,
        positionB: Double, idB: UUID
    ) -> Bool {
        positionA != positionB
            ? positionA < positionB
            : idA.uuidString < idB.uuidString
    }
}
