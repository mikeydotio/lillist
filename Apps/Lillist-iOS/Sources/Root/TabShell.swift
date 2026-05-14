import SwiftUI

/// Compact-size shell: a tab bar with Today / All / Filters / Search,
/// matching design Section 7's iOS subsection.
struct TabShell: View {
    @State private var selection: Tab = .today
    @State private var isQuickCapturePresented = false

    enum Tab: Hashable { case today, all, filters, search }

    private var selectionOptional: Binding<Tab?> {
        Binding(
            get: { selection },
            set: { if let new = $0 { selection = new } }
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(Tab.today)

            NavigationStack {
                AllTagsView()
            }
            .tabItem { Label("All", systemImage: "tag") }
            .tag(Tab.all)

            NavigationStack {
                FiltersListView()
            }
            .tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
            .tag(Tab.filters)

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(Tab.search)
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingPlusOverlay(isPresented: $isQuickCapturePresented)
        }
        .sheet(isPresented: $isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents([.fraction(0.35), .medium])
                .presentationDragIndicator(.visible)
        }
        .lillistKeyboardShortcuts(
            isQuickCapturePresented: $isQuickCapturePresented,
            selectedTab: selectionOptional
        )
    }
}
