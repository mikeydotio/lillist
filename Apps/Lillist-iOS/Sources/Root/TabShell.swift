import SwiftUI
import LillistUI

/// Compact-size shell: a tab bar with Today / All / Filters / Search,
/// matching design Section 7's iOS subsection.
///
/// Plan 16 Task 29: `isQuickCapturePresented` and `selection` are
/// owned by `LillistApp` (so `LillistCommands` can bind to them from
/// outside any view); TabShell reads them via env values.
struct TabShell: View {
    @Environment(\.isQuickCapturePresentedBinding) private var isQuickCapturePresented
    @Environment(\.selectedSectionBinding) private var selectedSection
    @State private var isSettingsPresented = false
    @AppStorage("hasCapturedTask") private var hasCapturedTask = false
    @State private var quickCaptureDetent: PresentationDetent = .large

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
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(iPadSection.today)

            NavigationStack {
                AllTagsView()
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("All", systemImage: "tag") }
            .tag(iPadSection.all)

            NavigationStack {
                FiltersListView()
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
            .tag(iPadSection.filters)

            NavigationStack {
                SearchView()
                    .modifier(SettingsToolbarItem(isPresented: $isSettingsPresented))
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(iPadSection.search)
        }
        .environment(\.quickCaptureAction, { isQuickCapturePresented.wrappedValue = true })
        .tabViewBottomAccessory {
            FloatingAddButton(onTap: { isQuickCapturePresented.wrappedValue = true })
                .accessibilityIdentifier("QuickCaptureAccessory")
        }
        .sheet(isPresented: isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents(
                    [.fraction(0.35), .medium, .large],
                    selection: $quickCaptureDetent
                )
                .presentationDragIndicator(.visible)
                .onAppear {
                    // Re-derive the initial detent each time the sheet
                    // presents so the first-capture-defaults-to-large
                    // semantic from Plan 16 survives, while still letting
                    // subsequent drags persist for the sheet's lifetime.
                    quickCaptureDetent = hasCapturedTask ? .fraction(0.35) : .large
                }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
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
