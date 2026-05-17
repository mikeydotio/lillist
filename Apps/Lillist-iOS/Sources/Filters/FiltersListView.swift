import SwiftUI
import LillistCore
import LillistUI

// MARK: - Accessibility audit (Plan 8, Task 26)
// - Filter rows use Label(name, systemImage:) — text is the accessibility label.
// - Sections (Pinned / All Filters) become VoiceOver headers automatically.
// - No fixed font sizes; semantic colors only.

/// Saved smart filters, pinned-first per design Section 7's iOS subsection.
struct FiltersListView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var pinned: [SmartFilterStore.SmartFilterRecord] = []
    @State private var others: [SmartFilterStore.SmartFilterRecord] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load filters",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if pinned.isEmpty && others.isEmpty {
                ContentUnavailableView {
                    Label("No filters yet", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Pre-installed filters land on first sync.")
                }
                // No CTA — filter creation isn't an iOS surface yet.
                // When it lands, add a "Create filter" Button here.
            } else {
                List {
                    if !pinned.isEmpty {
                        Section("Pinned") {
                            ForEach(pinned, id: \.id) { filter in
                                NavigationLink(value: FilterDestination(id: filter.id)) {
                                    FilterRow(filter: filter)
                                }
                            }
                        }
                    }
                    if !others.isEmpty {
                        Section("All Filters") {
                            ForEach(others, id: \.id) { filter in
                                NavigationLink(value: FilterDestination(id: filter.id)) {
                                    FilterRow(filter: filter)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Filters")
        .navigationDestination(for: FilterDestination.self) { dest in
            FilterResultsView(filterID: dest.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusBadge(indicator: env.syncMonitor.indicator)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
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

private struct FilterRow: View {
    let filter: SmartFilterStore.SmartFilterRecord

    var body: some View {
        Label(filter.name, systemImage: filter.isPinned ? "pin.fill" : "line.3.horizontal.decrease.circle")
    }
}

struct FilterDestination: Hashable {
    let id: UUID
}
