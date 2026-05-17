import SwiftUI
import LillistCore
import LillistUI

/// Plan 15 Task 9: SwiftUI `MenuBarExtra` scene that replaces the
/// AppKit-bridge `StatusBarController`. The popover content is the
/// existing `TodayPopoverView` plus a Quick Capture primary action and
/// a "Open Lillist" affordance. The `isInserted:` binding lets the
/// scene be removed at runtime when the user disables the
/// status-bar icon in Preferences (no relaunch needed).
///
/// `.menuBarExtraStyle(.window)` opens an anchored panel below the
/// status item (instead of the default `.menu` style which renders an
/// NSMenu). The panel auto-anchors above-or-below based on screen
/// position — no manual `preferredEdge:` calculation.
///
/// Accepts an optional `AppEnvironment` so the scene can be declared
/// unconditionally at App-body level (the SceneBuilder type-checker
/// is happier without an `if let` wrapping the scene); when the
/// environment is still loading, the popover renders a "Loading…"
/// placeholder.
struct MenuBarExtraScene: Scene {
    @Binding var isInserted: Bool
    let environment: AppEnvironment?
    let onQuickCapture: () -> Void

    var body: some Scene {
        MenuBarExtra(
            "Lillist",
            systemImage: "checklist",
            isInserted: $isInserted
        ) {
            popoverContent
                .frame(width: 320, height: 400)
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var popoverContent: some View {
        if let environment {
            MenuBarPopover(onQuickCapture: onQuickCapture)
                .environment(environment)
        } else {
            ProgressView("Loading Lillist…")
        }
    }
}

private struct MenuBarPopover: View {
    @Environment(\.openWindow) private var openWindow
    let onQuickCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lillist").font(.headline)
                Spacer()
                Button("Quick Capture", systemImage: "plus.circle.fill") {
                    onQuickCapture()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Quick Capture (⌃⌥Space)")
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
            Divider()
            TodayPopoverView()
            Divider()
            HStack {
                Button("Open Lillist") {
                    NSApp.activate(ignoringOtherApps: true)
                    for w in NSApp.windows where w.title == "Lillist" {
                        w.makeKeyAndOrderFront(nil); return
                    }
                    // Plan 19 Task 12: if no Lillist window is currently
                    // open (the user ⌘W-closed it), fall through to the
                    // same reopen path the Dock icon uses.
                    NotificationCenter.default.post(name: .lillistReopenMainWindow, object: nil)
                }
                // Plan 19 Task 12: explicit affordance for users with the
                // menu-bar item visible. Goes through the same notification
                // as `applicationShouldHandleReopen`, so the Dock-icon path
                // and this button share their reopen logic.
                Button("Show Main Window") {
                    NotificationCenter.default.post(name: .lillistReopenMainWindow, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}
