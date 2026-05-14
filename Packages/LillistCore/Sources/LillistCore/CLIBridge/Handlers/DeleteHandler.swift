import Foundation

extension CLIBridge {
    public enum DeleteHandler {
        public static func run(token: String, persistence: PersistenceController) async throws {
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .destructive, persistence: persistence
            )
            try await TaskStore(persistence: persistence).softDelete(id: r.id)
        }
    }
}
