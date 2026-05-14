import Foundation
import CoreData

extension CLIBridge {
    public enum EvalHandler {
        public static func run(
            groupJSON: String,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar
        ) async throws -> [TaskStore.TaskRecord] {
            guard let data = groupJSON.data(using: .utf8) else {
                throw LillistError.validationFailed([.init(field: "predicate", message: "expression must be UTF-8")])
            }
            let group: PredicateGroup
            do {
                group = try JSONDecoder().decode(PredicateGroup.self, from: data)
            } catch {
                throw LillistError.validationFailed([.init(field: "predicate", message: "invalid predicate JSON: \(error.localizedDescription)")])
            }
            let predicate = NSPredicateCompiler.compile(group, now: now, calendar: calendar)
            let ctx = persistence.container.viewContext
            return try await ctx.perform {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = predicate
                return try ctx.fetch(req).map { LsHandler.record(from: $0) }
            }
        }
    }
}
