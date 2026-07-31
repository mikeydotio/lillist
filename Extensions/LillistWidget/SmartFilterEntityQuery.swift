import AppIntents

import LillistCore

/// Supplies the widget-configuration picker with the user's saved smart filters.
///
/// A thin AppIntents adapter over ``LillistCore/WidgetFilterCatalog``, which owns
/// the policy: cheap snapshot-index read first, live store only as a bounded
/// enhancement, and no store read at all when the answer is already known.
///
/// `LIL-91`: this type previously opened the live Core Data store
/// unconditionally and without a time bound. Because WidgetKit must resolve a
/// widget's configuration intent *before* it will request a timeline, a blocked
/// store open here meant `timeline(for:in:)` was never called at all and the
/// widget rendered only its container background. The catalog's doc comment
/// records the three defects (C1 sentinel short-circuit, C2 bounded wait, C3
/// cheap-source-first) in full.
struct SmartFilterEntityQuery: EntityQuery {
    func entities(for identifiers: [SmartFilterEntity.ID]) async throws -> [SmartFilterEntity] {
        let resolution = await Self.catalog.resolve(ids: Set(identifiers))
        var result: [SmartFilterEntity] = []
        if resolution.includesUnfiltered { result.append(.noFilter) }
        result += resolution.saved.map(SmartFilterEntity.init)
        return result
    }

    /// "No Filter" leads the list so it's the obvious default; saved filters follow.
    func suggestedEntities() async throws -> [SmartFilterEntity] {
        let saved = await Self.catalog.filters()
        return [.noFilter] + saved.map(SmartFilterEntity.init)
    }

    /// Both sources resolve through the App Group. `nil` from either means
    /// *unavailable* (so the next source is tried); an empty array means
    /// *authoritatively no saved filters*, which is an answer, not a miss.
    private static let catalog = WidgetFilterCatalog(
        indexRead: {
            guard let store = WidgetSnapshotStore(appGroupID: WidgetIntentSupport.appGroupID) else {
                return nil
            }
            return store.readIndex()?.filters
        },
        liveRead: {
            guard let persistence = try? await WidgetIntentSupport.makePersistence(),
                  let records = try? await SmartFilterStore(persistence: persistence).list()
            else { return nil }
            return records.map { .init(id: $0.id, name: $0.name, tintHex: $0.tintColor) }
        }
    )
}
