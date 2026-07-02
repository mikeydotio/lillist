import WidgetKit

import LillistCore

/// One timeline entry: the resolved snapshot (nil when the cache is cold and a
/// rebuild couldn't run) plus the widget's configuration.
struct FilterEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let configuration: SelectFilterIntent
}

/// Sample data for the widget gallery / placeholder / redacted states.
enum WidgetSnapshotSamples {
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            filterID: UUID(),
            filterName: "Todayish",
            tintHex: "#8B45E8",
            generatedAt: Date(),
            totalCount: 5,
            openCount: 4,
            tasks: [
                .init(id: UUID(), title: "Submit feedback", status: .todo),
                .init(id: UUID(), title: "Custom router bit", status: .started),
                .init(id: UUID(), title: "Renew passport", status: .todo),
                .init(id: UUID(), title: "Docs for Toni", status: .todo),
            ]
        )
    }
}

/// Reads the per-filter snapshot cache the app maintains — the normal path never
/// touches Core Data. A cold cache (snapshot absent) triggers a single, bounded
/// one-shot rebuild for just the configured filter, then re-reads.
struct FilterTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = FilterEntry
    typealias Intent = SelectFilterIntent

    func placeholder(in context: Context) -> FilterEntry {
        FilterEntry(date: Date(), snapshot: WidgetSnapshotSamples.placeholder, configuration: SelectFilterIntent())
    }

    func snapshot(for configuration: SelectFilterIntent, in context: Context) async -> FilterEntry {
        let snapshot = await loadSnapshot(filterID: configuration.filter?.id) ?? WidgetSnapshotSamples.placeholder
        return FilterEntry(date: Date(), snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: SelectFilterIntent, in context: Context) async -> Timeline<FilterEntry> {
        let snapshot = await loadSnapshot(filterID: configuration.filter?.id)
        let entry = FilterEntry(date: Date(), snapshot: snapshot, configuration: configuration)
        // Backstop refresh; real-time freshness comes from the app's / extensions'
        // WidgetCenter.reloadAllTimelines() after each write.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(next))
    }

    /// Normal path: read the cached JSON. Cold cache: rebuild just this filter
    /// once (the only place the timeline touches Core Data), then re-read.
    private func loadSnapshot(filterID: UUID?) async -> WidgetSnapshot? {
        guard let store = WidgetSnapshotStore(appGroupID: WidgetIntentSupport.appGroupID) else { return nil }
        guard let id = filterID ?? store.readIndex()?.filters.first?.id else { return nil }
        if let cached = store.read(filterID: id) { return cached }
        guard let persistence = try? await WidgetIntentSupport.makePersistence() else { return nil }
        let builder = WidgetSnapshotBuilder(
            smartFilterStore: SmartFilterStore(persistence: persistence),
            snapshotStore: store
        )
        await builder.regenerate(filterIDs: [id])
        return store.read(filterID: id)
    }
}
