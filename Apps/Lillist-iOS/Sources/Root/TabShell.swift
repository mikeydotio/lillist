import SwiftUI

/// Compact-size shell: a tab bar with Today / All / Filters / Search,
/// matching design Section 7's iOS subsection.
struct TabShell: View {
    @State private var selection: Tab = .today
    @State private var isQuickCapturePresented = false
    @State private var isSettingsPresented = false

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
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(Tab.today)

            NavigationStack {
                AllTagsView()
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("All", systemImage: "tag") }
            .tag(Tab.all)

            NavigationStack {
                FiltersListView()
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
            .tag(Tab.filters)

            NavigationStack {
                SearchView()
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
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
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
        }
        .lillistKeyboardShortcuts(
            isQuickCapturePresented: $isQuickCapturePresented,
            selectedTab: selectionOptional
        )
    }
}

/// Plan 10 Task 14: small reusable gear-icon toolbar item that
/// presents the Settings sheet. Applied to each tab's NavigationStack
/// content so the entry point is discoverable from any tab.
struct SettingsToolbarItem: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}
