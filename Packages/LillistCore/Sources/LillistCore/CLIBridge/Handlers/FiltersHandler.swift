import Foundation

extension CLIBridge {
    public enum FiltersHandler {
        public static func list(persistence: PersistenceController) async throws -> [SmartFilterStore.SmartFilterRecord] {
            try await SmartFilterStore(persistence: persistence).list()
        }

        public static func show(name: String, persistence: PersistenceController) async throws -> SmartFilterStore.SmartFilterRecord {
            try await SmartFilterStore(persistence: persistence).fetch(byName: name)
        }

        public static func run(
            name: String,
            sort: SortField,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar
        ) async throws -> [TaskStore.TaskRecord] {
            try await LsHandler.run(
                flags: FilterFlags(),
                savedFilterName: name,
                sort: sort,
                persistence: persistence,
                now: now,
                calendar: calendar
            )
        }

        @discardableResult
        public static func save(
            name: String,
            group: PredicateGroup,
            sortField: SortField,
            persistence: PersistenceController
        ) async throws -> UUID {
            try await SmartFilterStore(persistence: persistence).create(
                name: name,
                group: group,
                sortField: sortField,
                sortAscending: true
            )
        }

        public static func delete(name: String, persistence: PersistenceController) async throws {
            try await SmartFilterStore(persistence: persistence).delete(byName: name)
        }
    }
}
