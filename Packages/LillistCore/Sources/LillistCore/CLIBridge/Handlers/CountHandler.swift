import Foundation

extension CLIBridge {
    public enum CountHandler {
        public static func run(
            flags: FilterFlags,
            savedFilterName: String?,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar
        ) async throws -> Int {
            let records = try await LsHandler.run(
                flags: flags,
                savedFilterName: savedFilterName,
                sort: .createdAt,
                persistence: persistence,
                now: now,
                calendar: calendar
            )
            return records.count
        }
    }
}
