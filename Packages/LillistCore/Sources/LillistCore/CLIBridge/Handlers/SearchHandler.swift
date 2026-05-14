import Foundation
import CoreData

extension CLIBridge {
    public enum SearchHandler {
        public static func run(
            query: String,
            scopeToken: String?,
            persistence: PersistenceController
        ) async throws -> [TaskStore.TaskRecord] {
            // Resolve the optional scope task first.
            let scopeID: UUID?
            if let st = scopeToken {
                let r = try await Resolver.resolve(
                    token: st, scope: .anywhereIncludingClosed,
                    destructiveness: .readOnly, persistence: persistence
                )
                scopeID = r.id
            } else {
                scopeID = nil
            }

            let ctx = persistence.container.viewContext
            return try await ctx.perform {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = NSPredicate(format: "deletedAt == nil")
                let all = try ctx.fetch(req)

                let scoped: [LillistTask]
                if let scopeID {
                    scoped = all.filter { task in
                        var cursor: LillistTask? = task.parent
                        var depth = 0
                        while let node = cursor, depth < 64 {
                            if node.id == scopeID { return true }
                            cursor = node.parent
                            depth += 1
                        }
                        return false
                    }
                } else {
                    scoped = all
                }

                let hits = scoped.filter { task in
                    let title = task.title ?? ""
                    let notes = task.notes ?? ""
                    return title.localizedStandardContains(query) || notes.localizedStandardContains(query)
                }
                return hits.map { LsHandler.record(from: $0) }
            }
        }
    }
}
