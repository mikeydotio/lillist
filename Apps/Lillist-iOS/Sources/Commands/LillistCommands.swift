import SwiftUI
import LillistUI

/// Scene-level command surface. Exposes hardware-keyboard shortcuts to
/// the iPadOS hold-⌘ overlay (which only enumerates `CommandMenu` /
/// `CommandGroup` entries — not arbitrary `.keyboardShortcut` bindings
/// buried inside views).
///
/// Plan 16 replaces the previous hidden-Button hack in
/// `KeyboardShortcuts.swift`. `⌘N` previously bound to Quick Capture
/// collides with iPadOS's system "New Window" — moved to `⌘⇧N`.
struct LillistCommands: Commands {
    @Binding var isQuickCapturePresented: Bool
    @Binding var selectedSection: iPadSection?

    var body: some Commands {
        CommandMenu("Lillist") {
            Button("New Task") {
                isQuickCapturePresented = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Today") { selectedSection = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("All") { selectedSection = .all }
                .keyboardShortcut("2", modifiers: .command)
            Button("Filters") { selectedSection = .filters }
                .keyboardShortcut("3", modifiers: .command)
            Button("Search") { selectedSection = .search }
                .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Find in Lillist…") { selectedSection = .search }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}
