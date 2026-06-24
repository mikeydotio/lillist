import CoreSpotlight
import Foundation
import LillistCore

/// Pure (testable) mappers for the Spotlight indexing pipeline.
/// Co-compiled into the standalone macOS test bundle so
/// `IndexingServiceTests` can exercise the attribute-set and
/// searchable-item construction without standing up the full
/// `IndexingService` (which depends on `AppEnvironment`).
enum IndexingMappers {
    /// Canonical domain identifier — used by both `CSSearchableItem`
    /// (for grouping) and `CSSearchableIndex.delete(domainIdentifier:)`
    /// (for purging on uninstall / app reset).
    static let domainIdentifier = "app.lillist.task"

    /// Constructs the `CSSearchableItemAttributeSet` for a task. Pure
    /// function — no Core Data access, no Spotlight side effects —
    /// so tests can assert on the attribute set without standing up
    /// a real index.
    static func attributeSet(
        for record: TaskStore.TaskRecord,
        tagNames: [String]
    ) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = record.title
        attrs.contentDescription = record.notes.isEmpty ? nil : record.notes
        attrs.keywords = tagNames
        return attrs
    }

    /// Constructs the full `CSSearchableItem` (attribute set + IDs)
    /// for a task. Pairs with `attributeSet(for:tagNames:)`.
    static func searchableItem(
        for record: TaskStore.TaskRecord,
        tagNames: [String]
    ) -> CSSearchableItem {
        CSSearchableItem(
            uniqueIdentifier: record.id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet(for: record, tagNames: tagNames)
        )
    }
}
