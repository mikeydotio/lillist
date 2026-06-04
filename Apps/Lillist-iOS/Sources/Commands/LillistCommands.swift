import SwiftUI
import LillistUI

/// Scene-level command surface. Exposes hardware-keyboard shortcuts to
/// the iPadOS hold-⌘ overlay (which only enumerates `CommandMenu` /
/// `CommandGroup` entries — not arbitrary `.keyboardShortcut` bindings
/// buried inside views).
///
/// The 3-tab restructure collapsed the previous section/search command
/// surface into a single primary `TasksView`. iOS exposes only Quick
/// Capture as a hardware-keyboard shortcut (`⌘⇧N`, avoiding the
/// iPadOS-reserved `⌘N`); the status-mutation and indent/outdent
/// commands were removed because no iOS surface observed their
/// notifications.
struct LillistCommands: Commands {
    @Binding var isQuickCapturePresented: Bool

    var body: some Commands {
        CommandMenu("Lillist") {
            Button("New Task") {
                isQuickCapturePresented = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
