import Foundation

extension CLIBridge {
    public enum NudgeHandler {
        /// Persists a nudge `NotificationSpec` against the resolved task.
        ///
        /// Per the Plan-5 deviation note in the Plan-6 plan: the CLI does not
        /// own a `NotificationScheduler` (it would be wrong to wire one up in
        /// a short-lived offline process). The spec is just persisted; the
        /// running macOS / iOS app reconciles it into a `UNNotificationRequest`
        /// the next time it launches or its event bridge fires.
        @discardableResult
        public static func run(
            token: String,
            atToken: String,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar
        ) async throws -> UUID {
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )
            let when = try DateParsing.parse(atToken, now: now, calendar: calendar)
            let specs = NotificationSpecStore(persistence: persistence)
            return try await specs.add(
                taskID: r.id,
                kind: .nudge,
                offsetMinutes: nil,
                fireDate: when.date
            )
        }
    }
}
