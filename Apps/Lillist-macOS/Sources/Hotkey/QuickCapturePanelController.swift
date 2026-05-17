import AppKit
import SwiftUI
import LillistCore
import LillistUI

/// Hosts `QuickCaptureView` in a borderless NSPanel that floats above other windows.
@MainActor
final class QuickCapturePanelController {
    private var panel: NSPanel?
    private var text: String = ""
    let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    func toggle() {
        if let p = panel, p.isVisible { close(); return }
        present()
    }

    func present() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true // Plan 15 Task 16: drop shadow under borderless panel

        let host = NSHostingController(
            rootView: QuickCaptureView(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                onSubmit: { [weak self] r in self?.submit(r) },
                onCancel: { [weak self] in self?.close() }
            )
            .environment(environment)
        )
        panel.contentView = host.view

        // Plan 15 Task 13: place on the screen under the cursor (or
        // primary if the cursor isn't over any screen — e.g. a
        // disconnected display) at ~1/3 from the top of that screen's
        // visible frame. `placementOrigin` is a pure helper for tests.
        let target = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? .main
        let screenFrame = target?.frame ?? .zero
        let visibleFrame = target?.visibleFrame ?? .zero
        let origin = QuickCapturePlacementMath.placementOrigin(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            panelSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)

        panel.makeKeyAndOrderFront(nil)
        // Plan 15 Task 15: do NOT call NSApp.activate(ignoringOtherApps:)
        // — that defeats `.nonactivatingPanel` and steals menu bar focus
        // from whatever app the user was in. The panel can be key
        // without bringing the app forward.

        // Plan 15 Task 14: dismiss when the panel resigns key (e.g. the
        // user clicked away or hit ⌘Tab to switch apps).
        installResignKeyObserver(on: panel)

        self.panel = panel
    }

    private func installResignKeyObserver(on panel: NSPanel) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        text = ""
    }

    private func submit(_ r: QuickCaptureParser.Result) {
        let title = r.title
        let tags = r.tags
        Task { @MainActor in
            guard let id = try? await environment.taskStore.create(title: title) else { return }
            for tagName in tags {
                if let tagID = try? await environment.tagStore.findOrCreate(name: tagName, parent: nil) {
                    try? await environment.taskStore.assignTag(taskID: id, tagID: tagID)
                }
            }
            self.close()
        }
    }
}
