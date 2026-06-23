import SwiftUI
import AppKit
import LillistCore
import LillistUI

/// Commands wires the menu bar items and the keyboard shortcuts called out in
/// design Section 7. Each command posts a `Notification` that the relevant view
/// observes; this keeps the commands target-agnostic.
struct LillistCommands: Commands {
    let environment: AppEnvironment
    @FocusedValue(\.listColumn) private var listColumn: ListColumn?

    var body: some Commands {
        // Multi-window deferred — Plan 19 Task 3.
        // `CommandGroup(replacing: .newItem)` removed SwiftUI's implicit
        // ⌘N "New Window". Restoring it requires multi-window correctness
        // verification (independent RootSplitView state per window,
        // OnboardingPresentationModifier not re-firing on already-onboarded
        // users, focus-routing across windows). The shared `AppEnvironment`
        // pattern is Core-Data-safe, but the SwiftUI-state side needs an
        // eyeball pass that wasn't possible during Plan 19's autonomous
        // execution. Land ⌥⌘N "New Window" in a follow-up plan once the
        // verification can be driven interactively.
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                NotificationCenter.default.post(name: .lillistNewTask, object: nil)
            }.keyboardShortcut("n", modifiers: [.command])

            Button("New Sibling Task") {
                NotificationCenter.default.post(name: .lillistNewSibling, object: nil)
            }.keyboardShortcut(.return, modifiers: [.command, .shift])
        }

        CommandMenu("Task") {
            // Space advances the status one step forward (todo → started →
            // closed), matching the iOS status-cube tap. The notification
            // symbol is still named `.lillistToggleStarted` for historical
            // reasons — it predates the one-way cycle change.
            Button("Advance Status") {
                NotificationCenter.default.post(name: .lillistToggleStarted, object: nil)
            }.keyboardShortcut(.space, modifiers: [])
              .disabled(TaskListShortcutGate.isDisabled(listColumn: listColumn))

            Button("Mark Closed") {
                NotificationCenter.default.post(name: .lillistMarkClosed, object: nil)
            }.keyboardShortcut(.return, modifiers: [.command])
              .disabled(TaskListShortcutGate.isDisabled(listColumn: listColumn))

            Button("Mark Blocked & Schedule Follow-up") {
                NotificationCenter.default.post(name: .lillistMarkBlocked, object: nil)
            }.keyboardShortcut(".", modifiers: [.command])
              .disabled(TaskListShortcutGate.isDisabled(listColumn: listColumn))

            // Open the highlighted task in the unified editor. Plain Return
            // (⌘Return is "Mark Closed"); list-focus-gated so it never fires
            // while a TextField is first responder. Single-click also opens
            // (via the row's tap), so this is the keyboard-nav-mode path.
            Button("Open Task") {
                NotificationCenter.default.post(name: .lillistOpenTaskEditor, object: nil)
            }.keyboardShortcut(.return, modifiers: [])
              .disabled(TaskListShortcutGate.isDisabled(listColumn: listColumn))
        }

        CommandMenu("View") {
            Button("Focus Sidebar") {
                NotificationCenter.default.post(name: .lillistFocusSidebar, object: nil)
            }.keyboardShortcut("1", modifiers: [.command])
            Button("Focus List") {
                NotificationCenter.default.post(name: .lillistFocusList, object: nil)
            }.keyboardShortcut("2", modifiers: [.command])
            // "Focus Detail" (⌘3) retired — the docked detail column is gone.
        }

        // Plan 15 Task 29: ⌃⌘S toggles the sidebar (Mac convention,
        // matching Mail / Notes / Reminders). The toolbar button from
        // Task 1 also flips columnVisibility; this menu command goes
        // through a notification so the View has a single handler.
        CommandGroup(after: .sidebar) {
            Button("Show Sidebar") {
                NotificationCenter.default.post(name: .lillistToggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
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
        // so the item is honest about its destination — the README is the
        // de-facto docs during alpha; revisit if a dedicated docs site lands.
        CommandGroup(replacing: .help) {
            Link("Lillist on GitHub", destination: URL(string: "https://github.com/mikeydotio/Lillist")!)
        }
    }
}
