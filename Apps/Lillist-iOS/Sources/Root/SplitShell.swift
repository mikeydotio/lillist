import SwiftUI
import LillistUI

/// Regular-size shell for iPad. Two-column `NavigationSplitView` mirroring
/// macOS's middle+detail columns. The tab bar collapses into a sidebar list.
/// Design Section 7 iOS subsection.
struct SplitShell: View {
    @State private var selection: iPadSection? = .today
    @State private var isQuickCapturePresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationSplitView {
            List(iPadSection.allCases, selection: $selection) { section in
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
            selectedTab: $selection
        )
    }
}
