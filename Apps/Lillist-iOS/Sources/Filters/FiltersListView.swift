import SwiftUI
import LillistCore
import LillistUI

/// Thin wrapper around `LillistUI.FiltersListScreen`. Owns the
/// pinned/others fetch and the `.navigationDestination(for: UUID.self)`
/// that turns a tapped filter into a `FilterResultsView`. Plan 20a
/// Task 4c.
struct FiltersListView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var pinned: [SmartFilterStore.SmartFilterRecord] = []
    @State private var others: [SmartFilterStore.SmartFilterRecord] = []
    @State private var loadError: String?

    var body: some View {
        FiltersListScreen(
            pinned: pinned,
            others: others,
            loadError: loadError,
            syncIndicator: env.syncMonitor.indicator,
            onRefresh: { await reload() },
            trailingSections: {
                // The 3-tab restructure moves the tag tree out of the tab
                // bar and parks it here as a single "Tags" entry. Discovery
                // stays one level deeper but the top-level information
                // architecture (Today / All / Filters) stays focused.
                Section(String(localized: "Tags")) {
                    NavigationLink {
                        AllTagsView()
                    } label: {
                        Label(String(localized: "Tags"), systemImage: "tag")
                    }
                }
            }
        )
        .navigationDestination(for: UUID.self) { id in
            FilterResultsView(filterID: id)
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            let all = try await env.smartFilterStore.list()
            pinned = all.filter(\.isPinned).sorted { $0.position < $1.position }
            others = all.filter { !$0.isPinned }.sorted { $0.position < $1.position }
            loadError = nil
        } catch {
            loadError = "\(error)"
            pinned = []
            others = []
        }
    }
}
