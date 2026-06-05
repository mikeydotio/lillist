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

        /// Pure step: given the previously-emitted snapshot (keyed by id) and the
        /// freshly-evaluated current record set, returns the records to emit as
        /// updates and the snapshot to carry forward. A record is emitted when it
        /// is new to the set or differs from its previous value; unchanged records
        /// are suppressed (dedup). Emission order follows `current`.
        ///
        /// `previous == nil` means "first evaluation": every current record is
        /// emitted.
        public static func snapshotStep(
            previous: [UUID: TaskStore.TaskRecord]?,
            current: [TaskStore.TaskRecord]
        ) -> (toEmit: [TaskStore.TaskRecord], next: [UUID: TaskStore.TaskRecord]) {
            var next: [UUID: TaskStore.TaskRecord] = [:]
            next.reserveCapacity(current.count)
            var toEmit: [TaskStore.TaskRecord] = []
            for record in current {
                next[record.id] = record
                if let prev = previous {
                    if prev[record.id] != record {
                        toEmit.append(record)
                    }
                } else {
                    toEmit.append(record)
                }
            }
            return (toEmit, next)
        }

        /// Serializes coalesced re-evaluation requests so context-change bursts
        /// produce one ordered pass, never interleaved detached Tasks.
        private actor Coalescer {
            private var pending = false
            private var running = false

            /// Marks work pending; returns true if the caller should start the
            /// drain loop (i.e. no drain is already running).
            func requestAndShouldStart() -> Bool {
                pending = true
                if running { return false }
                running = true
                return true
            }

            /// Consumes the pending flag at the top of a drain iteration.
            /// Returns false when there is nothing left to do (drain exits).
            func consume() -> Bool {
                if pending {
                    pending = false
                    return true
                }
                running = false
                return false
            }
        }

        /// Actor-isolated holder for the last-emitted snapshot, ensuring that
        /// the single serialized drain loop can safely read and write without
        /// strict-concurrency capture violations.
        private actor SnapshotBox {
            var value: [UUID: TaskStore.TaskRecord] = [:]

            func swap(_ new: [UUID: TaskStore.TaskRecord]) {
                value = new
            }

            func get() -> [UUID: TaskStore.TaskRecord] {
                value
            }
        }

        /// Streams events for matching tasks. Emits an initial `insert` event for
        /// every record currently matching, then re-evaluates on each
        /// `NSManagedObjectContextObjectsDidChange`. Re-evaluations are serialized
        /// and debounced through a single long-lived drain Task (no per-notification
        /// detached Tasks), deduped against the last emitted snapshot, and any
        /// evaluation error is surfaced via `onError` instead of being swallowed.
        /// The function never returns under normal conditions — the CLI process is
        /// terminated by SIGINT/SIGTERM.
        public static func run(
            flags: FilterFlags,
            savedFilterName: String?,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar,
            debounce: Duration = .milliseconds(50),
            emit: @escaping @Sendable (Event) -> Void,
            onError: @escaping @Sendable (Error) -> Void = { _ in }
        ) async throws {
            // Bootstrap with the current matching set as inserts.
            let initial = try await LsHandler.run(
                flags: flags, savedFilterName: savedFilterName, sort: .createdAt,
                persistence: persistence, now: now, calendar: calendar
            )
            let box = SnapshotBox()
            for r in initial {
                await box.swap(await box.get().merging([r.id: r]) { _, new in new })
                emit(Event(kind: .insert, task: TaskRenderer.TaskDTO(from: r), at: Date()))
            }

            let ctx = persistence.container.viewContext
            let center = NotificationCenter.default
            let flagsCopy = flags
            let nameCopy = savedFilterName
            let calendarCopy = calendar
            let coalescer = Coalescer()

            // A single, serialized drain loop. Each notification requests a pass;
            // bursts collapse into one re-evaluation.
            @Sendable func drain() async {
                while await coalescer.consume() {
                    try? await Task.sleep(for: debounce)
                    do {
                        let after = try await LsHandler.run(
                            flags: flagsCopy, savedFilterName: nameCopy, sort: .createdAt,
                            persistence: persistence, now: Date(), calendar: calendarCopy
                        )
                        let prev = await box.get()
                        let (toEmit, next) = snapshotStep(previous: prev, current: after)
                        await box.swap(next)
                        for r in toEmit {
                            emit(Event(kind: .update, task: TaskRenderer.TaskDTO(from: r), at: Date()))
                        }
                    } catch {
                        onError(error)
                    }
                }
            }

            let token = center.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: ctx,
                queue: nil
            ) { _ in
                Task {
                    if await coalescer.requestAndShouldStart() {
                        await drain()
                    }
                }
            }
            defer { center.removeObserver(token) }

            // Park the task until cancellation.
            try await Task.sleep(nanoseconds: UInt64.max)
        }
    }
}
