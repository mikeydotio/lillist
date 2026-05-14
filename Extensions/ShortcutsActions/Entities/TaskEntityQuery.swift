import AppIntents
import LillistCore

/// Looks up tasks by ID and produces recent-task suggestions for Shortcuts.
/// Constructs a fresh `PersistenceController` per invocation against the
/// App-Group-shared store so the extension sees the same data as the main
/// app.
struct TaskEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskEntity.ID]) async throws -> [TaskEntity] {
        let persistence = try await Self.makePersistence()
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
        let persistence = try await Self.makePersistence()
        let filters = SmartFilterStore(persistence: persistence)
        let recent = PredicateGroup(
            combinator: .all,
            predicates: [
                .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false))),
                .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]
        )
        let records = try await filters.evaluate(group: recent, sort: .modifiedAt, ascending: false)
        return records.prefix(20).map(TaskEntity.init)
    }

    static func makePersistence() async throws -> PersistenceController {
        let config = StoreConfiguration.appGroupOnDisk(
            groupID: "group.io.mikeydotio.Lillist"
        ) ?? (try .defaultOnDisk)
        return try await PersistenceController(configuration: config)
    }
}
