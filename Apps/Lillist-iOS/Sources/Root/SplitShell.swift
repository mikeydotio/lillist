import SwiftUI

/// Regular-size shell for iPad. Two-column `NavigationSplitView` mirroring
/// macOS's middle+detail columns. The tab bar collapses into a sidebar list.
/// Design Section 7 iOS subsection.
struct SplitShell: View {
    enum Section: Hashable, CaseIterable, Identifiable {
        case today, all, filters, search
        var id: Self { self }
        var title: String {
            switch self {
            case .today: return "Today"
            case .all: return "All"
            case .filters: return "Filters"
            case .search: return "Search"
            }
        }
        var systemImage: String {
            switch self {
            case .today: return "sun.max"
            case .all: return "tag"
            case .filters: return "line.3.horizontal.decrease.circle"
            case .search: return "magnifyingglass"
            }
        }
    }

    @State private var selection: Section? = .today
    @State private var isQuickCapturePresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .navigationTitle("Lillist")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        } detail: {
            NavigationStack {
                switch selection ?? .today {
                case .today: TodayView()
                case .all: AllTagsView()
                case .filters: FiltersListView()
                case .search: SearchView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isQuickCapturePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New task")
                    .accessibilityHint("Opens quick capture")
                }
            }
        }
        .sheet(isPresented: $isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents([.fraction(0.35), .medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
        }
        .lillistKeyboardShortcuts(
            isQuickCapturePresented: $isQuickCapturePresented,
            selectedTab: Binding(
                get: { selection?.asTabShellTab },
                set: { selection = $0?.asSection }
            )
        )
    }
}

extension SplitShell.Section {
    var asTabShellTab: TabShell.Tab {
        switch self {
        case .today: return .today
        case .all: return .all
        case .filters: return .filters
        case .search: return .search
        }
    }
}

extension TabShell.Tab {
    var asSection: SplitShell.Section {
        switch self {
        case .today: return .today
        case .all: return .all
        case .filters: return .filters
        case .search: return .search
        }
    }
}
