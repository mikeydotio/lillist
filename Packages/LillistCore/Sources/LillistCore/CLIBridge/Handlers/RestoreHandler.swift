import Foundation
import CoreData

extension CLIBridge {
    public enum RestoreHandler {
        public static func run(token: String, persistence: PersistenceController) async throws {
            // Trashed tasks aren't in the default scope; resolve directly through the trash list.
            let trashed = try await TaskStore(persistence: persistence).trashed()
            let id = try resolveTrashed(token: token, trashed: trashed)
            try await TaskStore(persistence: persistence).restore(id: id)
        }

        /// Throws if `token` does not resolve to exactly one trashed task.
        /// Used by the batch `restore` command to confirm every token is
        /// restorable before restoring any (all-or-nothing).
        public static func preflight(token: String, trashed: [TaskStore.TaskRecord]) throws {
            _ = try resolveTrashed(token: token, trashed: trashed)
        }

        /// Resolves a token against the trash list: full UUID, else exact
        /// (case-insensitive) title. Throws `.notFound`/`.ambiguous`.
        static func resolveTrashed(token: String, trashed: [TaskStore.TaskRecord]) throws -> UUID {
            if let parsed = UUID(uuidString: token) {
                guard trashed.contains(where: { $0.id == parsed }) else { throw LillistError.notFound }
                return parsed
            }
            let lower = token.lowercased()
            let exact = trashed.filter { $0.title.lowercased() == lower }
            guard exact.isEmpty == false else { throw LillistError.notFound }
            if exact.count > 1 { throw LillistError.ambiguous(exact.map(\.id)) }
            return exact[0].id
        }
    }
}
