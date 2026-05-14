import Foundation

extension CLIBridge {
    public enum EditHandler {
        public static func run(
            token: String,
            newTitle: String?,
            newNotes: String?,
            startToken: String?,
            deadlineToken: String?,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar
        ) async throws {
            let resolution = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )
            let tasks = TaskStore(persistence: persistence)
            let start = try startToken.map { try DateParsing.parse($0, now: now, calendar: calendar) }
            let deadline = try deadlineToken.map { try DateParsing.parse($0, now: now, calendar: calendar) }
            try await tasks.update(id: resolution.id) { draft in
                if let t = newTitle { draft.title = t }
                if let n = newNotes { draft.notes = n }
                if let s = start {
                    draft.start = s.date
                    draft.startHasTime = s.hasTime
                }
                if let d = deadline {
                    draft.deadline = d.date
                    draft.deadlineHasTime = d.hasTime
                }
            }
        }
    }
}
