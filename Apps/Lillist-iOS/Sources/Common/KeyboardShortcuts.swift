import SwiftUI
import LillistUI

/// Hardware keyboard shortcuts surfaced as a view modifier so both shells
/// can apply the same declaration. Design Section 7's cross-platform
/// conventions on iOS / iPadOS:
///
/// - ⌘N — open Quick Capture
/// - ⌘1 / ⌘2 / ⌘3 / ⌘4 — switch to Today / All / Filters / Search
/// - ⌘⇧F — jump to Search
struct LillistKeyboardShortcuts: ViewModifier {
    @Binding var isQuickCapturePresented: Bool
    @Binding var selectedTab: iPadSection?

    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    Button("New Task") { isQuickCapturePresented = true }
                        .keyboardShortcut("n", modifiers: .command)
                    Button("Today") { selectedTab = .today }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("All") { selectedTab = .all }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("Filters") { selectedTab = .filters }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("Search") { selectedTab = .search }
                        .keyboardShortcut("4", modifiers: .command)
                    Button("Search (anywhere)") { selectedTab = .search }
                        .keyboardShortcut("f", modifiers: [.command, .shift])
                }
                .hidden()
                .accessibilityHidden(true)
            )
    }
}

extension View {
    func lillistKeyboardShortcuts(
        isQuickCapturePresented: Binding<Bool>,
        selectedTab: Binding<iPadSection?>
    ) -> some View {
        modifier(LillistKeyboardShortcuts(
            isQuickCapturePresented: isQuickCapturePresented,
            selectedTab: selectedTab
        ))
    }
}
