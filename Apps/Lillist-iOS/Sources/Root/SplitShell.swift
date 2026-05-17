import SwiftUI
import LillistUI

/// Regular-size shell for iPad. Three-column `NavigationSplitView`
/// (sidebar → list → detail) mirroring macOS `RootSplitView` and the
/// HIG-canonical Mail / Reminders / Notes layout.
/// Design Section 7 iOS subsection.
struct SplitShell: View {
    @State private var selection: iPadSection? = .today
    @State private var taskSelection: UUID?
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
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
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
            .navigationSplitViewColumnWidth(min: 320, ideal: 460)
        } detail: {
            if let id = taskSelection {
                NavigationStack {
                    TaskDetailView(taskID: id)
                }
            } else {
                ContentUnavailableView(
                    "Select a task",
                    systemImage: "checklist",
                    description: Text("Pick a task from the list to see its details.")
                )
            }
        }
        .environment(\.taskSelectionBinding, $taskSelection)
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
