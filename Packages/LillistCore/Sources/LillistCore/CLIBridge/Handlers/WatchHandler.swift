import Foundation
import CoreData

extension CLIBridge {
    public enum WatchHandler {
        public struct Event: Codable, Sendable {
            public enum Kind: String, Codable, Sendable { case insert, update, delete }
            public let kind: Kind
            public let task: TaskRenderer.TaskDTO
            public let at: Date

            public init(kind: Kind, task: TaskRenderer.TaskDTO, at: Date) {
                self.kind = kind
                self.task = task
                self.at = at
            }
        }

        /// Streams events for matching tasks. Emits an initial `insert` event
        /// for every record currently matching, then re-evaluates on each
        /// `NSManagedObjectContextObjectsDidChange` and emits an `update` for
        /// every match. The function never returns under normal conditions —
        /// the CLI process is terminated by SIGINT/SIGTERM.
        ///
        /// Note: this is structurally wired against local context changes.
        /// CloudKit-driven remote changes flow through the same context once
        /// Plan 2's `NSPersistentCloudKitContainer` is fully attached.
        public static func run(
            flags: FilterFlags,
            savedFilterName: String?,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar,
            emit: @escaping @Sendable (Event) -> Void
        ) async throws {
            // Bootstrap with the current matching set.
            let initial = try await LsHandler.run(
                flags: flags, savedFilterName: savedFilterName, sort: .createdAt,
                persistence: persistence, now: now, calendar: calendar
            )
            for r in initial {
                emit(Event(kind: .insert, task: TaskRenderer.TaskDTO(from: r), at: Date()))
            }

            let ctx = persistence.container.viewContext
            let center = NotificationCenter.default
            let flagsCopy = flags
            let nameCopy = savedFilterName
            let calendarCopy = calendar

            let token = center.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: ctx,
                queue: nil
            ) { _ in
                Task {
                    do {
                        let after = try await LsHandler.run(
                            flags: flagsCopy, savedFilterName: nameCopy, sort: .createdAt,
                            persistence: persistence, now: Date(), calendar: calendarCopy
                        )
                        for r in after {
                            emit(Event(kind: .update, task: TaskRenderer.TaskDTO(from: r), at: Date()))
                        }
                    } catch {
                        // Watch is best-effort; swallow per-event errors.
                    }
                }
            }
            defer { center.removeObserver(token) }

            // Park the task until cancellation.
            try await Task.sleep(nanoseconds: UInt64.max)
        }
    }
}
