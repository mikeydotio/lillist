import Foundation

extension CLIBridge {
    public enum StatusHandler {
        public static func run(
            token: String,
            to newStatus: Status,
            note: String?,
            persistence: PersistenceController
        ) async throws {
            // Transition-to-closed is destructive per design Section 6.
            let destructiveness: Resolver.Destructiveness = (newStatus == .closed) ? .destructive : .readOnly
            let resolution = try await Resolver.resolve(
                token: token,
                scope: .anywhereIncludingClosed,
                destructiveness: destructiveness,
                persistence: persistence
            )
            let tasks = TaskStore(persistence: persistence)
            let journal = JournalStore(persistence: persistence)
            try await tasks.transition(id: resolution.id, to: newStatus)
            if let body = note, body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                _ = try await journal.appendNote(taskID: resolution.id, body: body)
            }
        }
    }
}
