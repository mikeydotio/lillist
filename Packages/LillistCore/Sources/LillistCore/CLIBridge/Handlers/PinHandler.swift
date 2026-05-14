import Foundation

extension CLIBridge {
    public enum PinHandler {
        public static func pin(token: String, persistence: PersistenceController) async throws {
            try await setPinned(token: token, value: true, persistence: persistence)
        }
        public static func unpin(token: String, persistence: PersistenceController) async throws {
            try await setPinned(token: token, value: false, persistence: persistence)
        }
        static func setPinned(token: String, value: Bool, persistence: PersistenceController) async throws {
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )
            try await TaskStore(persistence: persistence).update(id: r.id) { $0.isPinned = value }
        }
    }
}
