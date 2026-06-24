import SwiftUI
import AppKit
import LillistUI

/// Wires the macOS menu bar items and keyboard shortcuts that survive the
/// single-column main window. The window now hosts the shared iOS
/// `TasksScreen`, which has **no row-selection model** — so the former
/// selection- and sidebar-dependent commands (New Sibling, Advance
/// Status, Mark Closed, Mark Blocked, Open Task, Focus Sidebar/List, Show
/// Sidebar) were retired with the split view. Rows open by click into the
/// in-window unified editor; status changes happen on the row's status
/// control.
struct LillistCommands: Commands {
    /// ⌘N flips the same trigger the bottom-trailing FAB uses, opening the
    /// in-window unified editor's new-capture flow.
    @Binding var isQuickCapturePresented: Bool

    var body: some Commands {
        // Multi-window deferred. `CommandGroup(replacing: .newItem)`
        // removes SwiftUI's implicit ⌘N "New Window" and repurposes ⌘N as
        // "New Task". Restoring a real ⌥⌘N "New Window" needs multi-window
        // state correctness (per-window state, OnboardingPresentationModifier
        // not re-firing on already-onboarded users, focus routing) verified
        // interactively — land it in a follow-up.
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                isQuickCapturePresented = true
            }.keyboardShortcut("n", modifiers: [.command])
        }

        // Plan 15 Task 21: custom About panel with byline credit.
        CommandGroup(replacing: .appInfo) {
            Button("About Lillist") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .credits: NSAttributedString(
                        string: "Built by Mikey Ward",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                ])
            }
        }

        // Plan 15 Task 22: replace the default Help submenu with a single
        // Link to the repo. Labeled "Lillist on GitHub" rather than "Help"
        // so the item is honest about its destination.
        CommandGroup(replacing: .help) {
            Link("Lillist on GitHub", destination: URL(string: "https://github.com/mikeydotio/Lillist")!)
        }
    }
}
