import AppIntents
import Foundation

import LillistCore

/// The widget-configuration picker option: one saved smart filter. Built from
/// the value-type `SmartFilterStore.SmartFilterRecord` (or the widget snapshot
/// index) — no NSManagedObject crosses the boundary.
struct SmartFilterEntity: AppEntity, Identifiable {
    let id: UUID
    @Property(title: "Name") var name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Smart Filter"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
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
