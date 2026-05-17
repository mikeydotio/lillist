import SwiftUI
import LillistUI

/// Regular-size shell for iPad. Three-column `NavigationSplitView`
/// (sidebar → list → detail) mirroring macOS `RootSplitView` and the
/// HIG-canonical Mail / Reminders / Notes layout.
/// Design Section 7 iOS subsection.
///
/// Plan 16 Task 29: `isQuickCapturePresented` and `selection` are
/// owned by `LillistApp` so `LillistCommands` (Scene-level) can bind
/// to them. SplitShell reads them via env values.
struct SplitShell: View {
    @Environment(\.isQuickCapturePresentedBinding) private var isQuickCapturePresented
    @Environment(\.selectedSectionBinding) private var selection
    @State private var taskSelection: UUID?
    @State private var isSettingsPresented = false
    @AppStorage("hasCapturedTask") private var hasCapturedTask = false
    @State private var quickCaptureDetent: PresentationDetent = .large

    var body: some View {
        NavigationSplitView {
            List(iPadSection.allCases, selection: selection) { section in
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
                    .accessibilityLabel(String(localized: "Settings"))
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            NavigationStack {
                switch selection.wrappedValue ?? .today {
                case .today: TodayView()
                case .all: AllTagsView()
                case .filters: FiltersListView()
                case .search: SearchView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isQuickCapturePresented.wrappedValue = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "New task"))
                    .accessibilityHint(String(localized: "Opens quick capture"))
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
        .environment(\.quickCaptureAction, { isQuickCapturePresented.wrappedValue = true })
        .sheet(isPresented: isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents(
                    [.fraction(0.35), .medium, .large],
                    selection: $quickCaptureDetent
                )
                .presentationDragIndicator(.visible)
                .onAppear {
                    quickCaptureDetent = hasCapturedTask ? .fraction(0.35) : .large
                }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
        }
    }
}
