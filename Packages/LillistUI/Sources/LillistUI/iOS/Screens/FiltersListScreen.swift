#if os(iOS)
import SwiftUI
import LillistCore

/// Saved smart-filters list (pinned-first) reachable from the
/// "Filters" tab. Pure presentation — the hosting iOS app's
/// `FiltersListView` owns the @State for the loaded filter records,
/// the `.task` that fetches them, and the `.navigationDestination`
/// that turns a tapped filter's UUID into a `FilterResultsView`.
/// Plan 20a Task 4c.
public struct FiltersListScreen<TrailingSections: View>: View {
    public var pinned: [SmartFilterStore.SmartFilterRecord]
    public var others: [SmartFilterStore.SmartFilterRecord]
    public var loadError: String?
    public var syncIndicator: SyncIndicator
    public var onRefresh: @MainActor () async -> Void
    @ViewBuilder public var trailingSections: () -> TrailingSections

    public init(
        pinned: [SmartFilterStore.SmartFilterRecord],
        others: [SmartFilterStore.SmartFilterRecord],
        loadError: String? = nil,
        syncIndicator: SyncIndicator = .idle(lastSync: nil),
        onRefresh: @escaping @MainActor () async -> Void = {},
        @ViewBuilder trailingSections: @escaping () -> TrailingSections = { EmptyView() }
    ) {
        self.pinned = pinned
        self.others = others
        self.loadError = loadError
        self.syncIndicator = syncIndicator
        self.onRefresh = onRefresh
        self.trailingSections = trailingSections
    }

    public var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load filters",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if pinned.isEmpty && others.isEmpty && (TrailingSections.self == EmptyView.self) {
                ContentUnavailableView {
                    Label(String(localized: "No filters yet", bundle: .module),
                          systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Pre-installed filters land on first sync.")
                }
                // No CTA — filter creation isn't an iOS surface yet.
                // When it lands, add a "Create filter" Button here.
            } else {
                List {
                    if !pinned.isEmpty {
                        Section(String(localized: "Pinned", bundle: .module)) {
                            ForEach(pinned, id: \.id) { filter in
                                NavigationLink(value: filter.id) {
                                    FilterRow(filter: filter)
                                }
                            }
                        }
                    }
                    if !others.isEmpty {
                        Section(String(localized: "All Filters", bundle: .module)) {
                            ForEach(others, id: \.id) { filter in
                                NavigationLink(value: filter.id) {
                                    FilterRow(filter: filter)
                                }
                            }
                        }
                    }
                    trailingSections()
                }
            }
        }
        .navigationTitle(Text(String(localized: "Filters", bundle: .module)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusBadge(indicator: syncIndicator)
            }
        }
        .refreshable { await onRefresh() }
    }
}

extension FiltersListScreen where TrailingSections == EmptyView {
    /// Convenience for callers (and snapshot tests) that don't need to
    /// inject any additional sections.
    public init(
        pinned: [SmartFilterStore.SmartFilterRecord],
        others: [SmartFilterStore.SmartFilterRecord],
        loadError: String? = nil,
        syncIndicator: SyncIndicator = .idle(lastSync: nil),
        onRefresh: @escaping @MainActor () async -> Void = {}
    ) {
        self.init(
            pinned: pinned,
            others: others,
            loadError: loadError,
            syncIndicator: syncIndicator,
            onRefresh: onRefresh,
            trailingSections: { EmptyView() }
        )
    }
}

private struct FilterRow: View {
    let filter: SmartFilterStore.SmartFilterRecord

    var body: some View {
        Label(
            filter.name,
            systemImage: filter.isPinned ? "pin.fill" : "line.3.horizontal.decrease.circle"
        )
    }
}
#endif
