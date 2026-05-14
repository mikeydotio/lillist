import Foundation

extension CLIBridge {
    public enum AddHandler {
        /// Creates a new task. Returns the new UUID. Caller prints it.
        @discardableResult
        public static func run(
            title: String,
            notes: String,
            startToken: String?,
            deadlineToken: String?,
            tagNames: [String],
            parentToken: String?,
            statusToken: String?,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar
        ) async throws -> UUID {
            let tasks = TaskStore(persistence: persistence)
            let tags = TagStore(persistence: persistence)

            var parentID: UUID?
            if let token = parentToken {
                let resolution = try await Resolver.resolve(
                    token: token,
                    scope: .anywhere,
                    destructiveness: .readOnly,
                    persistence: persistence
                )
                parentID = resolution.id
            }

            let id = try await tasks.create(title: title, notes: notes, parent: parentID)

            if startToken != nil || deadlineToken != nil {
                let start = try startToken.map { try DateParsing.parse($0, now: now, calendar: calendar) }
                let deadline = try deadlineToken.map { try DateParsing.parse($0, now: now, calendar: calendar) }
                try await tasks.update(id: id) { draft in
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

            for name in tagNames {
                let tagID: UUID
                if let existing = try await firstTagWithName(name, store: tags) {
                    tagID = existing
                } else {
                    tagID = try await tags.create(name: name)
                }
                try await tasks.assignTag(taskID: id, tagID: tagID)
            }

            if let token = statusToken {
                guard let s = Self.status(from: token) else {
                    throw LillistError.validationFailed([.init(field: "status", message: "unknown status '\(token)'")])
                }
                if s != .todo {
                    try await tasks.transition(id: id, to: s)
                }
            }

            return id
        }

        public static func status(from token: String) -> Status? {
            switch token.lowercased() {
            case "todo": return .todo
            case "started": return .started
            case "blocked": return .blocked
            case "closed": return .closed
            default: return nil
            }
        }

        /// Recursively walks the tag tree looking for the first tag with this
        /// name (case- and whitespace-insensitive — matches `TagStore.findOrCreate`
        /// so Quick Capture and the CLI/App-Intent paths converge on the same
        /// tag for "errands" vs "Errands" vs " errands ").
        static func firstTagWithName(_ name: String, store: TagStore) async throws -> UUID? {
            let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return try await walkAndFind(needle: needle, parent: nil, store: store)
        }

        private static func walkAndFind(needle: String, parent: UUID?, store: TagStore) async throws -> UUID? {
            let children = try await store.children(of: parent)
            for c in children {
                if c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle {
                    return c.id
                }
                if let descendant = try await walkAndFind(needle: needle, parent: c.id, store: store) {
                    return descendant
                }
            }
            return nil
        }
    }
}
