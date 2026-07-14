import AppKit
import SwiftUI
import Observation
import LillistCore
import LillistUI

/// Hosts the unified `TaskEditorView` in a floating, non-activating `NSPanel`.
///
/// One panel, two modes (`quick` / `full`) that differ only in size — the panel
/// resizes as the SwiftUI mode flips (observed via `withObservationTracking`).
/// Singleton: the global hotkey is a no-op while a panel is open; a row-click
/// open re-targets the existing panel instead of spawning a second (see
/// `EditorOpenDecision`).
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
    let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    private static let panelWidth: CGFloat = 600
    private static let quickHeight: CGFloat = 168
    private static let fullHeight: CGFloat = 700

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

    /// Row click / Return: open an existing task in full mode, re-targeting an
    /// already-open panel rather than stacking.
    func open(taskID: UUID) {
        let decision = EditorOpenDecision.decide(isOpen: isOpen, request: .existing(taskID))
        switch decision {
        case .present:
            let m = TaskEditorModel(stores: stores, opening: .existing(taskID))
            present(model: m)
            Task { await m.load() }
        case .retarget(let id):
            let m = TaskEditorModel(stores: stores, opening: .existing(id))
            model = m
            hosting?.rootView = editorRoot(m)
            Task { await m.load() }
            resizeForMode(animated: false)
        case .noop:
            break
        }
    }

    // MARK: - Presentation

    private func present(model: TaskEditorModel) {
        self.model = model
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.quickHeight),
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
        panel.contentViewController = host
        self.hosting = host

        place(panel)
        panel.makeKeyAndOrderFront(nil)
        // NB: no NSApp.activate — `.nonactivatingPanel` keeps the user in
        // whatever app the hotkey fired from. No resign-key observer either:
        // the status Menu's popover resigns key, and that must not dismiss.

        self.panel = panel
        resizeForMode(animated: false)
        observeMode()
    }

    private func editorRoot(_ model: TaskEditorModel) -> AnyView {
        AnyView(
            TaskEditorView(
                model: model,
                onDismiss: { [weak self] in self?.close(cancelled: false) },
                onOpenSubtask: { [weak self] id in self?.open(taskID: id) },
                onAddAttachment: { [weak self] in self?.presentAttachmentPicker() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(LillistSpacing.l)
            .onExitCommand { [weak self] in self?.close(cancelled: true) }
        )
    }

    /// Re-arming `@Observable` watcher: resize the panel whenever the editor's
    /// mode flips (the quick→full grow).
    private func observeMode() {
        guard let model else { return }
        withObservationTracking {
            _ = model.mode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                self.resizeForMode(animated: true)
                self.observeMode() // re-arm
            }
        }
    }

    private func resizeForMode(animated: Bool) {
        guard let panel, let model else { return }
        let targetHeight = model.mode == .full ? Self.fullHeight : Self.quickHeight
        var frame = panel.frame
        let delta = targetHeight - frame.size.height
        guard abs(delta) > 0.5 else { return }
        // Pin the top edge: growing downward keeps the title field in place.
        frame.origin.y -= delta
        frame.size.height = targetHeight
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
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        model = nil
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .lillistTasksDidChange, object: nil)
    }
}
