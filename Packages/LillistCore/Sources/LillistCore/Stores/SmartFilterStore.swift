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
