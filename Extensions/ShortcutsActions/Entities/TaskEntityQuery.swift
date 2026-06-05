import AppIntents
import LillistCore

/// Looks up tasks by ID and produces recent-task suggestions for Shortcuts.
///
/// Persistence is acquired through `IntentSupport.makePersistence()`, the
/// single gated factory every Lillist intent shares: it consults
/// `MigrationGate` (so a foreground sync-mode migration is never raced) and
/// honours the user's `syncMode` (so a LocalOnly user is never silently
/// opened with CloudKit mirroring attached). When the gate aborts, the
/// thrown `LillistError.storeUnavailable` propagates out of `entities` /
/// `suggestedEntities` — Shortcuts surfaces the "try again in a moment"
/// message instead of running against a half-swapped store.
struct TaskEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskEntity.ID]) async throws -> [TaskEntity] {
        let persistence = try await IntentSupport.makePersistence()
        let store = TaskStore(persistence: persistence)
        var out: [TaskEntity] = []
        for id in identifiers {
            if let record = try? await store.fetch(id: id) {
                out.append(TaskEntity(record))
            }
        }
        return out
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        let persistence = try await IntentSupport.makePersistence()
        let filters = SmartFilterStore(persistence: persistence)
        let recent = PredicateGroup(
            combinator: .all,
            predicates: [
                .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false))),
                .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]
        )
        let records = try await filters.evaluate(
            group: recent,
            sort: .modifiedAt,
            ascending: false,
            limit: 20
        )
        return records.map(TaskEntity.init)
    }
}
