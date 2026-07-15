import AppKit
import SwiftUI
import LillistCore
import LillistUI

/// Hosts the unified `TaskEditorView` in a floating, non-activating `NSPanel`.
///
/// One panel that follows its hosted editor's height: the `NSHostingController`
/// reports the SwiftUI content's ideal size as `preferredContentSize` (KVO), and
/// the panel re-fits to it — so quick/full and child-route sizes fall out of the
/// content, not hardcoded per-mode constants. Singleton: the global hotkey is a
/// no-op while a panel is open; a row-click open re-targets the existing panel
/// instead of spawning a second (see `EditorOpenDecision`).
///
/// The panel never activates Lillist (`.nonactivatingPanel`, no `NSApp.activate`)
/// so it floats over whatever app the global hotkey fired from. Unlike the old
/// quick-capture panel it does **not** dismiss on resign-key — the status
/// `Menu` opens a child popover (which resigns key) and the user may reference
/// another app mid-edit; dismissal is explicit (Done / Esc / close).
@MainActor
final class QuickCapturePanelController {
    private var panel: NSPanel?
    private var hosting: NSHostingController<AnyView>?
    private var model: TaskEditorModel?
    private var sizeObservation: NSKeyValueObservation?
    /// Tracks the last-applied mode so the panel animates only the discrete
    /// quick→full grow, not every incremental content-size change (typing).
    private var lastModeWasFull = false
    let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    private static let panelWidth: CGFloat = 600
    /// Seed height only — the panel then follows the editor's own content
    /// height (`preferredContentSize`), so quick/full/child-route sizes fall
    /// out of the SwiftUI layout instead of hardcoded per-mode constants.
    private static let seedHeight: CGFloat = 168

    private var stores: TaskEditorModel.Stores {
        TaskEditorModel.Stores(
            tasks: environment.taskStore,
            tags: environment.tagStore,
            series: environment.seriesStore,
            journal: environment.journalStore,
            attachments: environment.attachmentStore
        )
    }

    var isOpen: Bool { panel?.isVisible == true }

    // MARK: - Entry points

    /// Global hotkey / ⌘-capture: open a quick draft, or no-op if already open.
    func toggle() {
        switch EditorOpenDecision.decide(isOpen: isOpen, request: .quickCapture) {
        case .noop:
            return
        case .present:
            present(model: TaskEditorModel(stores: stores, opening: .newCapture(parentID: nil, placement: .top)))
        case .retarget:
            break // unreachable for quickCapture
        }
    }

    // MARK: - Presentation

    private func present(model: TaskEditorModel) {
        self.model = model
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.seedHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true

        let host = NSHostingController(rootView: editorRoot(model))
        // Let the hosting controller report the SwiftUI content's ideal size
        // as `preferredContentSize`, which we observe to size the panel.
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        self.hosting = host

        place(panel)
        panel.makeKeyAndOrderFront(nil)
        // NB: no NSApp.activate — `.nonactivatingPanel` keeps the user in
        // whatever app the hotkey fired from. No resign-key observer either:
        // the status Menu's popover resigns key, and that must not dismiss.

        self.panel = panel
        self.lastModeWasFull = model.mode == .full
        // Force an initial layout pass so `preferredContentSize` is populated,
        // then size the panel synchronously — the panel opens at its content
        // height instead of visibly animating up from the seed height.
        host.view.layoutSubtreeIfNeeded()
        fitPanelToContent(animated: false)
        observeContentSize()
    }

    private func editorRoot(_ model: TaskEditorModel) -> AnyView {
        AnyView(
            TaskEditorView(
                model: model,
                onDismiss: { [weak self] in self?.close(cancelled: false) },
                onAddAttachment: { [weak self] in self?.presentAttachmentPicker() }
            )
            // Fixed width, intrinsic height: the card self-sizes vertically so
            // the panel can hug it (no `.infinity` fill, which would peg the
            // reported size to the panel and defeat self-sizing).
            .padding(LillistSpacing.l)
            .frame(width: Self.panelWidth)
            .onExitCommand { [weak self] in self?.close(cancelled: true) }
        )
    }

    /// Follow the editor's content height: re-fit the panel whenever the
    /// hosted view's `preferredContentSize` changes — the quick→full grow,
    /// a child-route drill-in, or the description growing as the user types.
    private func observeContentSize() {
        sizeObservation = hosting?.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                // Animate only the discrete quick→full grow; incremental
                // content growth (the notes field growing as the user types)
                // re-fits instantly so the window doesn't jitter mid-typing.
                let isFull = self.model?.mode == .full
                let animate = isFull != self.lastModeWasFull
                self.lastModeWasFull = isFull
                self.fitPanelToContent(animated: animate)
            }
        }
    }

    private func fitPanelToContent(animated: Bool) {
        guard let panel, let hosting else { return }
        let target = hosting.preferredContentSize
        // Ignore the pre-layout zero size; clamp to the screen so an XXXL
        // editor can't grow the panel past the visible area.
        guard target.height > 1 else { return }
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
        let clampedHeight = min(target.height, visibleFrame?.height ?? target.height)
        var frame = panel.frame
        let delta = clampedHeight - frame.size.height
        guard abs(delta) > 0.5 else { return }
        // Pin the top edge (growing downward keeps the title field in place),
        // then keep the whole panel on-screen: a tall card must not push its
        // bottom — the Add commit button — below the visible frame / Dock.
        frame.origin.y -= delta
        frame.size.height = clampedHeight
        if let visibleFrame {
            frame.origin.y = min(max(frame.origin.y, visibleFrame.minY),
                                 visibleFrame.maxY - clampedHeight)
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(frame, display: true, animate: animated && !reduceMotion)
    }

    private func place(_ panel: NSPanel) {
        let target = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? .main
        let screenFrame = target?.frame ?? .zero
        let visibleFrame = target?.visibleFrame ?? .zero
        let origin = QuickCapturePlacementMath.placementOrigin(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            panelSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Attachment picker (macOS NSOpenPanel)

    private func presentAttachmentPicker() {
        guard let model else { return }
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [.image]
        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            Task { @MainActor in
                guard let data = try? Data(contentsOf: url) else { return }
                try? await model.addImageAttachment(filename: url.lastPathComponent, data: data)
            }
        }
    }

    // MARK: - Close

    /// Tear down the panel. `cancelled` (Esc / click-away analog) discards a
    /// capture draft; an explicit Done has already committed/live-saved.
    func close(cancelled: Bool = false) {
        if let model, cancelled, model.presentation == .capture {
            Task { await model.discard(); self.notifyChanged() }
        } else {
            notifyChanged()
        }
        sizeObservation?.invalidate()
        sizeObservation = nil
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        model = nil
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .lillistTasksDidChange, object: nil)
    }
}
