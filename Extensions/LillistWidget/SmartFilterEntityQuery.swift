import AppIntents

import LillistCore

/// Supplies the widget-configuration picker with the user's saved smart filters.
///
/// Runs only while the user is editing the widget (infrequent, user-initiated),
/// so a direct gated store read is fine here — the snapshot cache is for the
/// render-time fast path, not configuration. Falls back to the widget snapshot
/// index if the live store can't be opened.
struct SmartFilterEntityQuery: EntityQuery {
    func entities(for identifiers: [SmartFilterEntity.ID]) async throws -> [SmartFilterEntity] {
        let set = Set(identifiers)
        return await allFilters().filter { set.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SmartFilterEntity] {
        await allFilters()
    }

    private func allFilters() async -> [SmartFilterEntity] {
        if let persistence = try? await WidgetIntentSupport.makePersistence(),
           let records = try? await SmartFilterStore(persistence: persistence).list() {
            return records.map(SmartFilterEntity.init)
        }
        // Fallback: the last-written index (store unavailable / migration in flight).
        if let store = WidgetSnapshotStore(appGroupID: WidgetIntentSupport.appGroupID),
           let index = store.readIndex() {
            return index.filters.map(SmartFilterEntity.init)
        }
        return []
    }
}
