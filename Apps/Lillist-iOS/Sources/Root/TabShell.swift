import SwiftUI
import LillistUI

/// Compact-size shell: a three-tab bar — Today / All / Filters.
/// Search lifts out of the tab bar into a top-leading toolbar sheet
/// available on every section (RCA / 3-tab restructure). The tag tree
/// that used to be the "All" tab moves under Filters.
///
/// `isQuickCapturePresented` and `selection` are owned by `LillistApp`
/// so `LillistCommands` (Scene-level) can bind to them from outside any
/// view; TabShell reads them via env values.
struct TabShell: View {
    @Environment(\.isQuickCapturePresentedBinding) private var isQuickCapturePresented
    @Environment(\.isSearchPresentedBinding) private var isSearchPresentedEnv
    @Environment(\.selectedSectionBinding) private var selectedSection
    @Environment(\.filtersPathBinding) private var filtersPath
    @State private var isSettingsPresented = false

    /// `TabView(selection:)` wants a non-optional `iPadSection`; the
    /// scene-level binding is optional (so CommandMenu can reset
    /// selection during multi-window scenarios). Adapt by treating
    /// `nil` as `.today`.
    private var selection: Binding<iPadSection> {
        Binding(
            get: { selectedSection.wrappedValue ?? .today },
            set: { selectedSection.wrappedValue = $0 }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            NavigationStack {
                TodayView()
                    .modifier(SearchToolbarItem(isPresented: isSearchPresentedEnv))
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("Today", systemImage: iPadSection.today.systemImage) }
            .tag(iPadSection.today)

            NavigationStack {
                AllView()
                    .modifier(SearchToolbarItem(isPresented: isSearchPresentedEnv))
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("All", systemImage: iPadSection.all.systemImage) }
            .tag(iPadSection.all)

            // Filters tab's NavigationStack binds its path to the
            // scene-level `filtersPath` so the drilled-in destination
            // (`FiltersDestination.allTags` and onwards) survives
            // app relaunches. Other tabs intentionally use a fresh
            // stack each launch (per scope: no Task-Detail restore).
            NavigationStack(path: filtersPath) {
                FiltersListView()
                    .modifier(SearchToolbarItem(isPresented: isSearchPresentedEnv))
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("Filters", systemImage: iPadSection.filters.systemImage) }
            .tag(iPadSection.filters)
        }
        .environment(\.quickCaptureAction, { isQuickCapturePresented.wrappedValue = true })
        .tabViewBottomAccessory {
            FloatingAddButton(onTap: { isQuickCapturePresented.wrappedValue = true })
                .accessibilityIdentifier("QuickCaptureAccessory")
        }
        .modifier(QuickCaptureDialogHost(isPresented: isQuickCapturePresented))
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
        }
        .sheet(isPresented: isSearchPresentedEnv) {
            SearchSheet()
        }
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
                .accessibilityLabel(String(localized: "Settings"))
            }
        }
    }
}
