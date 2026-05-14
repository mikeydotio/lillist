import Foundation

extension CLIBridge {
    public enum TagsHandler {
        public static func list(persistence: PersistenceController) async throws -> [TagStore.TagRecord] {
            let store = TagStore(persistence: persistence)
            return try await walk(parent: nil, in: store)
        }

        static func walk(parent: UUID?, in store: TagStore) async throws -> [TagStore.TagRecord] {
            let children = try await store.children(of: parent)
            var out: [TagStore.TagRecord] = []
            for c in children {
                out.append(c)
                out.append(contentsOf: try await walk(parent: c.id, in: store))
            }
            return out
        }

        @discardableResult
        public static func add(name: String, tint: String?, parent: String?, persistence: PersistenceController) async throws -> UUID {
            let store = TagStore(persistence: persistence)
            var parentID: UUID?
            if let pt = parent {
                parentID = try await findTag(named: pt, store: store)
            }
            return try await store.create(name: name, tintColor: tint, parent: parentID)
        }

        public static func rename(name: String, to newName: String, persistence: PersistenceController) async throws {
            let store = TagStore(persistence: persistence)
            let id = try await findTag(named: name, store: store)
            try await store.rename(id: id, to: newName)
        }

        public static func move(name: String, newParent: String?, persistence: PersistenceController) async throws {
            let store = TagStore(persistence: persistence)
            let id = try await findTag(named: name, store: store)
            var parentID: UUID? = nil
            if let np = newParent {
                parentID = try await findTag(named: np, store: store)
            }
            try await store.reparent(id: id, newParent: parentID)
        }

        public static func delete(name: String, persistence: PersistenceController) async throws {
            let store = TagStore(persistence: persistence)
            let id = try await findTag(named: name, store: store)
            try await store.delete(id: id)
        }

        public static func tint(name: String, hex: String, persistence: PersistenceController) async throws {
            let store = TagStore(persistence: persistence)
            let id = try await findTag(named: name, store: store)
            try await store.setTintColor(id: id, hex: hex)
        }

        static func findTag(named name: String, store: TagStore) async throws -> UUID {
            let all = try await walk(parent: nil, in: store)
            let matches = all.filter { $0.name == name }
            if matches.isEmpty { throw LillistError.notFound }
            if matches.count > 1 { throw LillistError.ambiguous(matches.map(\.id)) }
            return matches[0].id
        }
    }
}
