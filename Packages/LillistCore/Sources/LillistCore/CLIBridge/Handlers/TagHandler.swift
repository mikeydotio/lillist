import Foundation

extension CLIBridge {
    public enum TagHandler {
        public static func run(
            token: String,
            tokens: [String],
            persistence: PersistenceController
        ) async throws {
            let resolution = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )
            let tasks = TaskStore(persistence: persistence)
            let tags = TagStore(persistence: persistence)
            for raw in tokens {
                let (op, name) = try parseToken(raw)
                let tagID: UUID
                if let existing = try await AddHandler.firstTagWithName(name, store: tags) {
                    tagID = existing
                } else {
                    tagID = try await tags.create(name: name)
                }
                switch op {
                case .add: try await tasks.assignTag(taskID: resolution.id, tagID: tagID)
                case .remove: try await tasks.unassignTag(taskID: resolution.id, tagID: tagID)
                }
            }
        }

        enum Op { case add, remove }

        static func parseToken(_ raw: String) throws -> (Op, String) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("+#") { return (.add, String(trimmed.dropFirst(2))) }
            if trimmed.hasPrefix("-#") { return (.remove, String(trimmed.dropFirst(2))) }
            if trimmed.hasPrefix("#") { return (.add, String(trimmed.dropFirst(1))) }
            throw LillistError.validationFailed([
                .init(field: "tag", message: "expected +#name, -#name, or #name; got '\(raw)'")
            ])
        }
    }
}
