import Foundation
import CoreData

extension CLIBridge {
    public enum RestoreHandler {
        public static func run(token: String, persistence: PersistenceController) async throws {
            // Trashed tasks aren't in the default scope; resolve directly through the trash list.
            let trashed = try await TaskStore(persistence: persistence).trashed()
            let id: UUID
            if let parsed = UUID(uuidString: token) {
                guard trashed.contains(where: { $0.id == parsed }) else { throw LillistError.notFound }
                id = parsed
            } else {
                let lower = token.lowercased()
                let exact = trashed.filter { $0.title.lowercased() == lower }
                guard exact.isEmpty == false else { throw LillistError.notFound }
                if exact.count > 1 { throw LillistError.ambiguous(exact.map(\.id)) }
                id = exact[0].id
            }
            try await TaskStore(persistence: persistence).restore(id: id)
        }
    }
}
