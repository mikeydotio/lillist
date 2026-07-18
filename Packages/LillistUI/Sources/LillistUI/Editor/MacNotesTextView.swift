#if os(macOS)
import SwiftUI
import AppKit

/// macOS notes editor: a self-measuring `NSTextView` that both **displays** and
/// **measures** its content, so the box hugs its text (like the iOS field) while
/// Return inserts a newline (issue #29).
///
/// This replaces the earlier invisible-`Text`-sizer approach (issue #36), which
/// drove the box height by wrapping a hidden SwiftUI `Text` offset from the live
/// `TextEditor` by four hand-tuned constants that *estimated* undocumented
/// `NSTextView` insets. Here the displayed view **is** the measured view, so the
/// metrics can't diverge and there is nothing to estimate — a future OS inset
/// change is reflected in the measurement automatically, and the height math is
/// host-unit-testable (`MacNotesTextMeasurerTests`), which offscreen glass
/// snapshots could never be.
struct MacNotesTextView: NSViewRepresentable {
    @Binding var text: String
    /// Two-way bridge to the editor's `@FocusState`. The parent maps
    /// `focusedField == .notes` in / out; this view reconciles it with the text
    /// view's first-responder status.
    @Binding var isFocused: Bool
    /// Empty-state prompt, drawn by the text view when the note is blank.
    var placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MacNotesTextConfig.makeTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.placeholderColor = LillistColor.textFaintNSColor
        textView.textColor = LillistColor.textBodyNSColor
        textView.insertionPointColor = LillistColor.textBodyNSColor
        var typing = MacNotesTextConfig.textAttributes
        typing[.foregroundColor] = LillistColor.textBodyNSColor
        textView.typingAttributes = typing
        // The AX text-area the macOS UITest (`MacNotesFieldUITests`) clicks and
        // types into; the placeholder value keeps VoiceOver announcing the hint.
        textView.setAccessibilityIdentifier("EditorNotesField")
        textView.setAccessibilityPlaceholderValue(placeholder)
        textView.string = text
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.reportFocusChange(focused)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        // Always allow scrolling (autohiding) rather than gating it on the
        // measured height: if a measurement is ever a hair low, the content
        // scrolls in place instead of clipping — the whole point of #36.
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MacNotesNSTextView else { return }
        context.coordinator.parent = self

        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
            textView.setAccessibilityPlaceholderValue(placeholder)
            textView.setNeedsDisplay(textView.bounds)
        }

        // Only reassign on a genuine external change (not our own typing), so the
        // undo stack and caret position survive keystrokes.
        if textView.string != text {
            let previous = textView.selectedRange()
            textView.string = text
            let location = min(previous.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.setNeedsDisplay(textView.bounds)
        }

        reconcileFocus(textView: textView, coordinator: context.coordinator)
    }

    /// Drive first-responder from `isFocused` (SwiftUI `@FocusState` → AppKit).
    /// Never touch the responder in `makeNSView` — the view has no `window` yet.
    private func reconcileFocus(textView: MacNotesNSTextView, coordinator: Coordinator) {
        guard let window = textView.window else { return }
        let isFirstResponder = window.firstResponder === textView
        guard isFocused != isFirstResponder else { return }
        coordinator.isProgrammaticFocusChange = true
        window.makeFirstResponder(isFocused ? textView : nil)
        coordinator.isProgrammaticFocusChange = false
    }

    /// Report the hugged height for the proposed width, measured with the shared
    /// config so it matches what the live view will render. Clamped to
    /// `[minHeight, editorNotesMaxHeight]`; past the cap the scroll view scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        if let proposed = proposal.width, proposed == 0 {
            return CGSize(width: 0, height: MacNotesTextConfig.minHeight)
        }
        let measureWidth: CGFloat
        if let proposed = proposal.width, proposed.isFinite, proposed > 0 {
            measureWidth = proposed
        } else if nsView.frame.width > 0 {
            measureWidth = nsView.frame.width
        } else {
            measureWidth = .greatestFiniteMagnitude
        }
        let height = MacNotesTextMeasurer.clamp(MacNotesTextMeasurer.height(of: text, width: measureWidth))
        let reportedWidth = (proposal.width?.isFinite ?? false) ? proposal.width! : measureWidth
        return CGSize(width: reportedWidth, height: height)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? MacNotesNSTextView {
            textView.onFocusChange = nil
            textView.delegate = nil
        }
        coordinator.invalidate()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacNotesTextView
        /// Set around our own `makeFirstResponder` calls so the resulting
        /// become/resign callbacks don't echo back into `isFocused`.
        var isProgrammaticFocusChange = false
        private var isValid = true

        init(_ parent: MacNotesTextView) { self.parent = parent }

        func invalidate() { isValid = false }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
            (textView as? MacNotesNSTextView).map { $0.setNeedsDisplay($0.bounds) }
        }

        func reportFocusChange(_ focused: Bool) {
            guard !isProgrammaticFocusChange, isValid else { return }
            // Defer the state write out of the AppKit responder callback.
            Task { @MainActor [weak self] in
                guard let self, self.isValid else { return }
                if self.parent.isFocused != focused { self.parent.isFocused = focused }
            }
        }
    }
}

// MARK: - NSTextView subclass

/// The macOS notes `NSTextView`: draws the empty-state placeholder and reports
/// first-responder changes so SwiftUI `@FocusState` can follow the caret.
final class MacNotesNSTextView: NSTextView {
    var placeholder: String = ""
    var placeholderColor: NSColor = .placeholderTextColor
    /// Invoked on the main actor when first-responder status changes.
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { onFocusChange?(true) }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { onFocusChange?(false) }
        return didResign
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        // We own the inset + padding, so the placeholder aligns exactly with the
        // caret origin — no estimation.
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height)
        placeholder.draw(at: origin, withAttributes: [
            .font: font ?? MacNotesTextConfig.font,
            .foregroundColor: placeholderColor,
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The dynamic NSColors re-resolve at draw time; force a redraw of the
        // drawn placeholder for the new appearance.
        setNeedsDisplay(bounds)
    }
}

// MARK: - Shared configuration (single source of truth)

/// The one place the macOS notes editor's text metrics are defined, so the live
/// view and the offscreen measurer are configured identically — "what is shown"
/// and "what is measured" cannot diverge.
@MainActor
enum MacNotesTextConfig {
    /// Plus Jakarta Sans body (15pt), matching `LillistTypography.body`; falls
    /// back to the system body font if the bundled face isn't registered.
    static let font: NSFont = LillistFonts.registerIfNeeded()
        ? (NSFont(name: "\(LillistFonts.familyStem)-Regular", size: 15) ?? .systemFont(ofSize: 15))
        : .systemFont(ofSize: 15)

    /// Text inset within the text view (applied identically by the live view and
    /// the measurer, so it only affects appearance, never line-count accuracy).
    /// Tunable; eyeball-verified on-device.
    static let textContainerInset = NSSize(width: 5, height: 8)

    /// Folded into `textContainerInset` (kept explicit and shared so the
    /// measurer's container matches the live container exactly).
    static let lineFragmentPadding: CGFloat = 0

    /// ~2 lines of body text — the iOS field's `.lineLimit(2...8)` floor.
    static let minHeight: CGFloat = 44
    /// Grow-to-here, then the `NSScrollView` scrolls in place.
    static var maxHeight: CGFloat { LillistSizing.editorNotesMaxHeight }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = .natural
        return style
    }

    /// Layout-affecting attributes shared by the live view and the measurer.
    static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraphStyle]
    }

    /// Builds an explicit **TextKit 1** stack (`NSTextStorage → NSLayoutManager →
    /// NSTextContainer → NSTextView`). Explicit construction pins TextKit 1, so
    /// `usedRect`/`layoutManager` reads are deterministic (a default macOS-15
    /// `NSTextView` is TextKit 2 with lazy layout).
    static func makeTextView() -> MacNotesNSTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = lineFragmentPadding
        layoutManager.addTextContainer(container)

        let textView = MacNotesNSTextView(frame: .zero, textContainer: container)
        textView.font = font
        textView.typingAttributes = textAttributes
        textView.textContainerInset = textContainerInset
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.autoresizingMask = [.width]
        return textView
    }
}

// MARK: - Measurer (host-testable)

/// Computes the content height an `NSTextView` needs to render a note at a given
/// width, using the **real** TextKit metrics — no estimation. Shares
/// `MacNotesTextConfig` with the live view, so a live-view render and a measured
/// height agree by construction. AppKit text layout composites offscreen without
/// a window, so this is unit-testable on the Mac host (`MacNotesTextMeasurerTests`).
@MainActor
enum MacNotesTextMeasurer {
    /// Raw (unclamped) content height for `text` laid out at `width`.
    static func height(of text: String, width: CGFloat) -> CGFloat {
        let textView = scratch
        guard let container = textView.textContainer,
              let layoutManager = textView.layoutManager,
              let storage = textView.textStorage else {
            return MacNotesTextConfig.minHeight
        }
        let inset = MacNotesTextConfig.textContainerInset
        container.widthTracksTextView = false
        container.size = NSSize(width: max(0, width - inset.width * 2), height: CGFloat.greatestFiniteMagnitude)
        storage.setAttributedString(NSAttributedString(string: text, attributes: MacNotesTextConfig.textAttributes))
        layoutManager.ensureLayout(for: container)
        var used = layoutManager.usedRect(for: container)
        // `usedRect` omits the trailing empty line (an empty document, or text
        // ending in "\n"): union the extra fragment so that line is counted.
        // This is what keeps a note ending in Return from clipping — it replaces
        // the old zero-width-space sizer hack.
        if layoutManager.extraLineFragmentTextContainer != nil {
            used = used.union(layoutManager.extraLineFragmentRect)
        }
        return ceil(used.height) + inset.height * 2
    }

    /// Clamp a raw height to the editor's floor and cap.
    static func clamp(_ raw: CGFloat) -> CGFloat {
        min(max(raw, MacNotesTextConfig.minHeight), MacNotesTextConfig.maxHeight)
    }

    /// A reusable offscreen text view configured exactly like the live one.
    private static let scratch: MacNotesNSTextView = MacNotesTextConfig.makeTextView()
}
#endif
