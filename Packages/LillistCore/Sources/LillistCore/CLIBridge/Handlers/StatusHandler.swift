import Foundation

extension CLIBridge {
    public enum StatusHandler {
        /// - Parameter notificationScheduler: X8 — property-injected into the
        ///   `TaskStore` this handler constructs so `transition`'s own
        ///   post-save reconcile actually fires. Defaults to `nil`, which
        ///   preserves the CLI's own deliberate, pre-existing behavior (see
        ///   `NudgeHandler`'s doc comment for why a genuinely short-lived,
        ///   one-shot CLI process does not get a scheduler — a Shortcuts/
        ///   App Intents caller, in contrast, passes one).
        public static func run(
            token: String,
            to newStatus: Status,
            note: String?,
            persistence: PersistenceController,
            notificationScheduler: (any NotificationReconciling)? = nil
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
            tasks.notificationScheduler = notificationScheduler
            let journal = JournalStore(persistence: persistence)
            try await tasks.transition(id: resolution.id, to: newStatus)
            if let body = note, body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                _ = try await journal.appendNote(taskID: resolution.id, body: body)
            }
        }
    }
}
