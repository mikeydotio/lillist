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
        var result: [SmartFilterEntity] = []
        if set.contains(WidgetSnapshot.unfilteredID) { result.append(.noFilter) }
        result += await allFilters().filter { set.contains($0.id) }
        return result
    }

    /// "No Filter" leads the list so it's the obvious default; saved filters follow.
    func suggestedEntities() async throws -> [SmartFilterEntity] {
        let saved = await allFilters()
        return [.noFilter] + saved
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
