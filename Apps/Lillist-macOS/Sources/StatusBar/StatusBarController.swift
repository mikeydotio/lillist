import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let environment: AppEnvironment
    private let onQuickCapture: () -> Void

    init(environment: AppEnvironment, onQuickCapture: @escaping () -> Void) {
        self.environment = environment
        self.onQuickCapture = onQuickCapture
        install()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Lillist")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quick Capture…", action: #selector(quickCapture), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Today's tasks", action: #selector(showToday), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Open Lillist", action: #selector(openMainWindow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lillist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: TodayPopoverView().environment(environment)
        )
        self.popover = popover
    }

    func uninstall() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    @objc private func quickCapture() { onQuickCapture() }

    @objc private func showToday() {
        guard let popover, let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == "Lillist" {
            window.makeKeyAndOrderFront(nil); return
        }
    }
}
