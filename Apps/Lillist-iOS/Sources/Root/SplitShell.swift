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

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .navigationTitle("Lillist")
        } detail: {
            NavigationStack {
                switch selection ?? .today {
                case .today: TodayView()
                case .all: AllTagsView()
                case .filters: FiltersListView()
                case .search: SearchView()
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingPlusOverlay(isPresented: $isQuickCapturePresented)
        }
        .sheet(isPresented: $isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents([.fraction(0.35), .medium])
        }
    }
}
