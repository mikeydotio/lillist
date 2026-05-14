import Foundation
import CoreData

extension TagStore {
    /// Look up a tag by `name` (case-insensitive, trimmed) under the given
    /// `parent` and return its ID, or atomically create it if absent.
    ///
    /// Atomic: the read and the optional write run inside a single
    /// `context.perform` block, so concurrent callers can't both miss the
    /// row and then both insert duplicates.
    ///
    /// Plan 7 uses this from Quick Capture's `#tag` flow.
    @discardableResult
    public func findOrCreate(
        name: String,
        parent: UUID? = nil,
        tintColor: String? = nil
    ) async throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateName(trimmed)

        let ctx = persistence.container.viewContext
        return try await ctx.perform { [self] in
            let parentTag: Tag?
            if let parent {
                parentTag = try fetchManagedObject(id: parent, in: ctx)
            } else {
                parentTag = nil
            }

            // Find existing under this parent with a case-insensitive name match.
            let req = NSFetchRequest<Tag>(entityName: "Tag")
            if let parentTag {
                req.predicate = NSPredicate(format: "parent == %@ AND name ==[c] %@", parentTag, trimmed)
            } else {
                req.predicate = NSPredicate(format: "parent == nil AND name ==[c] %@", trimmed)
            }
            req.fetchLimit = 1
            if let existing = try ctx.fetch(req).first, let id = existing.id {
                return id
            }

            let tag = Tag(context: ctx)
            let id = UUID()
            tag.id = id
            tag.name = trimmed
            tag.tintColor = tintColor
            tag.parent = parentTag
            tag.position = try nextPosition(forParent: parentTag)
            try ctx.save()
            return id
        }
    }
}
