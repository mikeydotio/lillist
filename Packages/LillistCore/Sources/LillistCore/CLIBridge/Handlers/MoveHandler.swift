import Foundation

extension CLIBridge {
    public enum MoveHandler {
        public static func run(
            token: String,
            newParentToken: String?,
            toRoot: Bool,
            persistence: PersistenceController
        ) async throws {
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .destructive, persistence: persistence
            )
            let newParent: UUID?
            if toRoot {
                newParent = nil
            } else if let pt = newParentToken {
                let pr = try await Resolver.resolve(
                    token: pt, scope: .anywhereIncludingClosed,
                    destructiveness: .destructive, persistence: persistence
                )
                newParent = pr.id
            } else {
                throw LillistError.validationFailed([
                    .init(field: "parent", message: "must specify a new parent or --root")
                ])
            }
            try await TaskStore(persistence: persistence).reparent(id: r.id, newParent: newParent)
        }
    }
}
