import Foundation
import CoreData

/// Persistence layer for saved smart filters. Serializes `PredicateGroup`
/// to JSON, stores it at `predicateGroupJSON`. Required-ness of `name` is
/// enforced here, not in the schema (CloudKit-compatibility rule).
public final class SmartFilterStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// Value-type DTO surfaced to callers. Never an `NSManagedObject`.
    public struct SmartFilterRecord: Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var group: PredicateGroup
        public var tintColor: String?
        public var sortField: SortField
        public var sortAscending: Bool
        public var isPinned: Bool
        public var position: Double
        public var createdAt: Date?
        public var modifiedAt: Date?

        public init(
            id: UUID,
            name: String,
            group: PredicateGroup,
            tintColor: String? = nil,
            sortField: SortField,
            sortAscending: Bool,
            isPinned: Bool,
            position: Double,
            createdAt: Date? = nil,
            modifiedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.group = group
            self.tintColor = tintColor
            self.sortField = sortField
            self.sortAscending = sortAscending
            self.isPinned = isPinned
            self.position = position
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
        }
    }

    /// Mutable view passed to `update`'s closure.
    public struct SmartFilterDraft {
        public var name: String
        public var group: PredicateGroup
        public var tintColor: String?
        public var sortField: SortField
        public var sortAscending: Bool
    }

    // MARK: - Create

    @discardableResult
    public func create(
        name: String,
        group: PredicateGroup,
        tintColor: String? = nil,
        sortField: SortField = .deadline,
        sortAscending: Bool = true
    ) async throws -> UUID {
        try validateName(name)
        let json = try Self.encode(group)
        return try await context.perform { [self] in
            let m = SmartFilter(context: context)
            let id = UUID()
            m.id = id
            m.name = name
            m.predicateGroupJSON = json
            m.tintColor = tintColor
            m.sortField = sortField
            m.sortAscending = sortAscending
            m.isPinned = false
            m.position = try nextPosition()
            m.createdAt = Date()
            m.modifiedAt = m.createdAt
            try context.save()
            return id
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> SmartFilterRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return try record(from: m)
        }
    }

    public func list() async throws -> [SmartFilterRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
            req.sortDescriptors = [
                NSSortDescriptor(key: "position", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            return try context.fetch(req).map { try record(from: $0) }
        }
    }

    // MARK: - Update

    public func update(id: UUID, _ block: @escaping @Sendable (inout SmartFilterDraft) -> Void) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let current = try record(from: m)
            var draft = SmartFilterDraft(
                name: current.name,
                group: current.group,
                tintColor: current.tintColor,
                sortField: current.sortField,
                sortAscending: current.sortAscending
            )
            block(&draft)
            try validateName(draft.name)
            m.name = draft.name
            m.predicateGroupJSON = try Self.encode(draft.group)
            m.tintColor = draft.tintColor
            m.sortField = draft.sortField
            m.sortAscending = draft.sortAscending
            m.modifiedAt = Date()
            try context.save()
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> SmartFilter {
        let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else {
            throw LillistError.notFound
        }
        return m
    }

    func nextPosition() throws -> Double {
        let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: false)]
        req.fetchLimit = 1
        let last = try context.fetch(req).first?.position
        return FractionalPosition.position(after: last, before: nil)
    }

    func validateName(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LillistError.validationFailed([
                .init(field: "name", message: "must not be empty")
            ])
        }
    }

    func record(from m: SmartFilter) throws -> SmartFilterRecord {
        let group: PredicateGroup
        if let json = m.predicateGroupJSON {
            group = try Self.decode(json)
        } else {
            group = .init(combinator: .all, predicates: [])
        }
        return SmartFilterRecord(
            id: m.id ?? UUID(),
            name: m.name ?? "",
            group: group,
            tintColor: m.tintColor,
            sortField: m.sortField,
            sortAscending: m.sortAscending,
            isPinned: m.isPinned,
            position: m.position,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt
        )
    }

    // MARK: - JSON codec

    static func encode(_ group: PredicateGroup) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(group)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ json: String) throws -> PredicateGroup {
        guard let data = json.data(using: .utf8) else {
            throw LillistError.validationFailed([
                .init(field: "predicateGroupJSON", message: "not valid UTF-8")
            ])
        }
        return try JSONDecoder().decode(PredicateGroup.self, from: data)
    }
}

extension SmartFilterStore {
    /// Fetch the saved filter with this exact name. Throws `notFound` when no
    /// row matches and `ambiguous` if multiple rows share the name.
    public func fetch(byName name: String) async throws -> SmartFilterRecord {
        let all = try await list()
        let matches = all.filter { $0.name == name }
        if matches.isEmpty { throw LillistError.notFound }
        if matches.count > 1 { throw LillistError.ambiguous(matches.map(\.id)) }
        return matches[0]
    }

    /// Delete the saved filter with this exact name.
    public func delete(byName name: String) async throws {
        let rec = try await fetch(byName: name)
        try await delete(id: rec.id)
    }
}

extension SmartFilterStore {
    public func setPinned(id: UUID, pinned: Bool) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.isPinned = pinned
            m.modifiedAt = Date()
            try context.save()
        }
    }

    /// Place `id` immediately between `after` and `before` (either may be nil).
    /// Uses `FractionalPosition` for gap-based insertion.
    public func reorder(id: UUID, after: UUID?, before: UUID?) async throws {
        try await context.perform { [self] in
            let target = try fetchManagedObject(id: id, in: context)
            let afterPos: Double? = try after.map { try fetchManagedObject(id: $0, in: context).position }
            let beforePos: Double? = try before.map { try fetchManagedObject(id: $0, in: context).position }
            if let a = afterPos, let b = beforePos, a >= b {
                throw LillistError.validationFailed([
                    .init(field: "reorder", message: "anchors out of order: after=\(a) before=\(b)")
                ])
            }
            target.position = FractionalPosition.position(after: afterPos, before: beforePos)
            target.modifiedAt = Date()
            try context.save()
        }
    }
}

extension SmartFilterStore {
    /// Evaluate a saved filter and return matching `TaskStore.TaskRecord`s,
    /// sorted by the filter's `sortField` / `sortAscending`. Trash exclusion
    /// is applied implicitly by the compiler unless the predicate explicitly
    /// references `inTrash`.
    public func evaluate(
        id: UUID,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [TaskStore.TaskRecord] {
        let rec = try await fetch(id: id)
        return try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(rec.group, now: now, calendar: calendar)
            req.sortDescriptors = Self.sortDescriptors(field: rec.sortField, ascending: rec.sortAscending)
            let tasks = try context.fetch(req)
            return tasks.map { Self.record(from: $0) }
        }
    }

    /// Evaluate an ad-hoc `PredicateGroup` (one that hasn't been persisted as
    /// a `SmartFilter`) and return matching `TaskStore.TaskRecord`s. Used by
    /// iOS Search and any caller that needs to run a filter without first
    /// saving it.
    ///
    /// Archived rows (`archivedAt != nil`) are excluded by default; pass
    /// `includeArchived: true` to surface them — the iOS Tasks view does
    /// this when the `.done` quick filter is selected so the "history"
    /// view shows everything completed.
    public func evaluate(
        group: PredicateGroup,
        sort: SortField = .modifiedAt,
        ascending: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeArchived: Bool = false
    ) async throws -> [TaskStore.TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(
                group,
                now: now,
                calendar: calendar,
                includeArchived: includeArchived
            )
            req.sortDescriptors = Self.sortDescriptors(field: sort, ascending: ascending)
            let tasks = try context.fetch(req)
            return tasks.map { Self.record(from: $0) }
        }
    }

    /// Count matching tasks without materializing records — for badge counts.
    public func count(
        id: UUID,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Int {
        let rec = try await fetch(id: id)
        return try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(rec.group, now: now, calendar: calendar)
            return try context.count(for: req)
        }
    }

    static func sortDescriptors(field: SortField, ascending: Bool) -> [NSSortDescriptor] {
        let primaryKey: String
        switch field {
        case .manualPosition, .deadline: primaryKey = "deadline"
        case .start: primaryKey = "start"
        case .title: primaryKey = "title"
        case .createdAt: primaryKey = "createdAt"
        case .modifiedAt: primaryKey = "modifiedAt"
        case .closedAt: primaryKey = "closedAt"
        case .status: primaryKey = "statusRaw"
        }
        return [
            NSSortDescriptor(key: primaryKey, ascending: ascending),
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
    }

    static func record(from m: LillistTask) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start,
            startHasTime: m.startHasTime,
            deadline: m.deadline,
            deadlineHasTime: m.deadlineHasTime,
            position: m.position,
            isPinned: m.isPinned,
            parentID: m.parent?.id,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt,
            closedAt: m.closedAt,
            archivedAt: m.archivedAt,
            deletedAt: m.deletedAt,
            seriesID: m.series?.id
        )
    }
}
