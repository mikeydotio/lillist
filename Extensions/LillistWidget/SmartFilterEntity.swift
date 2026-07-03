import AppIntents
import Foundation

import LillistCore

/// The widget-configuration picker option: one saved smart filter, or the
/// reserved **"No Filter"** sentinel (all tasks, unfiltered). Built from the
/// value-type `SmartFilterStore.SmartFilterRecord` (or the widget snapshot
/// index) — no NSManagedObject crosses the boundary.
struct SmartFilterEntity: AppEntity, Identifiable {
    let id: UUID
    @Property(title: "Name") var name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Smart Filter"

    /// The unfiltered "all tasks" option — the default for a freshly added
    /// widget. Its reserved id (``WidgetSnapshot/unfilteredID``) can never be a
    /// real `SmartFilter.id`.
    static let noFilter = SmartFilterEntity(id: WidgetSnapshot.unfilteredID, name: "No Filter")

    /// A subtitle + icon make "No Filter" unambiguous against a saved filter that
    /// happens to be named "No Filter" or has an empty name — saved filters show
    /// their name alone, with no subtitle.
    var displayRepresentation: DisplayRepresentation {
        if id == WidgetSnapshot.unfilteredID {
            return DisplayRepresentation(
                title: "No Filter",
                subtitle: "All tasks",
                image: .init(systemName: "tray.full")
            )
        }
        return DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = SmartFilterEntityQuery()

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

extension SmartFilterEntity {
    init(_ record: SmartFilterStore.SmartFilterRecord) {
        self.init(id: record.id, name: record.name)
    }

    init(_ entry: WidgetSnapshotIndex.Entry) {
        self.init(id: entry.id, name: entry.name)
    }
}
