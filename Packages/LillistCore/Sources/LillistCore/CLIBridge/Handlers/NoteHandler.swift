import Foundation

extension CLIBridge {
    public enum NoteHandler {
        @discardableResult
        public static func run(
            token: String,
            body: String,
            persistence: PersistenceController
        ) async throws -> UUID {
            guard body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw LillistError.validationFailed([.init(field: "body", message: "note body must not be empty")])
            }
            let resolution = try await Resolver.resolve(
                token: token, scope: .anywhere, destructiveness: .readOnly, persistence: persistence
            )
            return try await JournalStore(persistence: persistence).appendNote(taskID: resolution.id, body: body)
        }
    }
}
