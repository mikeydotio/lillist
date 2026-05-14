import Foundation
import CoreData

public final class TagStore: @unchecked Sendable {
    let persistence: PersistenceController
    var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct TagRecord: Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var tintColor: String?
        public var parentID: UUID?
        public var position: Double
    }

    // MARK: - Create

    @discardableResult
    public func create(name: String, tintColor: String? = nil, parent: UUID? = nil) async throws -> UUID {
        try validateName(name)
        return try await context.perform { [self] in
            let parentTag = try parent.map { try fetchManagedObject(id: $0, in: context) }
            let resolved = try uniqueNameUnder(parent: parentTag, desired: name)
            let tag = Tag(context: context)
            tag.id = UUID()
            tag.name = resolved
            tag.tintColor = tintColor
            tag.parent = parentTag
            tag.position = try nextPosition(forParent: parentTag)
            try context.save()
            return tag.id!
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> TagRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return record(from: m)
        }
    }

    public func children(of parentID: UUID?) async throws -> [TagRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<Tag>(entityName: "Tag")
            if let parentID {
                let parent = try fetchManagedObject(id: parentID, in: context)
                req.predicate = NSPredicate(format: "parent == %@", parent)
            } else {
                req.predicate = NSPredicate(format: "parent == nil")
            }
            req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            return try context.fetch(req).map(record(from:))
        }
    }

    // MARK: - Rename

    public func rename(id: UUID, to newName: String) async throws {
        try validateName(newName)
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.name != newName else { return }
            let resolved = try uniqueNameUnder(parent: m.parent, desired: newName, excluding: m)
            m.name = resolved
            try context.save()
        }
    }

    // MARK: - Reparent

    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let newParent: Tag?
            if let newParentID {
                let candidate = try fetchManagedObject(id: newParentID, in: context)
                if wouldCreateCycle(candidate: m, newParent: candidate) {
                    throw LillistError.validationFailed([
                        .init(field: "parent", message: "would create a cycle")
                    ])
                }
                newParent = candidate
            } else {
                newParent = nil
            }
            let resolved = try uniqueNameUnder(parent: newParent, desired: m.name ?? "", excluding: m)
            m.name = resolved
            m.parent = newParent
            m.position = try nextPosition(forParent: newParent)
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

    // MARK: - Tint

    /// Sets the tag's tint color. Used by the CLI's `lillist tags tint` and
    /// later by the macOS / iOS tag editors. The hex string is stored as-is —
    /// validation is the caller's job (`#RRGGBB` per design Section 2).
    public func setTintColor(id: UUID, hex: String?) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.tintColor = hex
            try context.save()
        }
    }

    // MARK: - Helpers

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> Tag {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    func nextPosition(forParent parent: Tag?) throws -> Double {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil")
        }
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: false)]
        req.fetchLimit = 1
        let last = try context.fetch(req).first?.position
        return FractionalPosition.position(after: last, before: nil)
    }

    private func uniqueNameUnder(parent: Tag?, desired: String, excluding: Tag? = nil) throws -> String {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil")
        }
        let siblings = try context.fetch(req)
        var existing = Set(siblings.compactMap(\.name))
        if let ex = excluding?.name { existing.remove(ex) }
        return Validators.uniqueName(desired: desired, existing: existing)
    }

    private func wouldCreateCycle(candidate: Tag, newParent: Tag?) -> Bool {
        guard let newParent else { return false }
        if candidate.objectID == newParent.objectID { return true }
        var cursor: Tag? = newParent.parent
        while let node = cursor {
            if node.objectID == candidate.objectID { return true }
            cursor = node.parent
        }
        return false
    }

    func validateName(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LillistError.validationFailed([
                .init(field: "name", message: "must not be empty")
            ])
        }
    }

    private func record(from m: Tag) -> TagRecord {
        TagRecord(
            id: m.id ?? UUID(),
            name: m.name ?? "",
            tintColor: m.tintColor,
            parentID: m.parent?.id,
            position: m.position
        )
    }
}
