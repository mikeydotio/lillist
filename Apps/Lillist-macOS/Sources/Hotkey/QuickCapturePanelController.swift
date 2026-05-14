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

        let host = NSHostingController(
            rootView: QuickCaptureView(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                onSubmit: { [weak self] r in self?.submit(r) },
                onCancel: { [weak self] in self?.close() }
            )
            .environment(environment)
        )
        panel.contentView = host.view
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
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
