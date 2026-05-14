import Foundation

extension CLIBridge {
    public enum ShowHandler {
        public struct Result: Sendable {
            public let task: TaskStore.TaskRecord
            public let journal: [JournalStore.JournalRecord]
            public let tagIDs: [UUID]
            public let pickedSilently: Bool
        }

        public static func run(
            token: String,
            persistence: PersistenceController
        ) async throws -> Result {
            let resolution = try await Resolver.resolve(
                token: token,
                scope: .anywhereIncludingClosed,
                destructiveness: .readOnly,
                persistence: persistence
            )
            let tasks = TaskStore(persistence: persistence)
            let journal = JournalStore(persistence: persistence)
            let task = try await tasks.fetch(id: resolution.id)
            let entries = try await journal.entries(forTask: resolution.id)
            let tagIDs = try await tasks.tagIDs(forTask: resolution.id)
            return Result(task: task, journal: entries, tagIDs: tagIDs, pickedSilently: resolution.pickedSilently)
        }
    }
}
