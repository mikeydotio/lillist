import SwiftUI
import LillistCore

/// The unified task editor — one cross-platform presentation with two modes
/// (`quick` / `full`) that differ only in size and which sections show.
///
/// Full mode is the compact **detail card** (issue #8): a dense header
/// (status + inline title + pin), a description box, a tag row, and three
/// summary lines — schedule, attachments, journal — that drill into in-card
/// child popups. A child *replaces* the card content and returns on Back; the
/// host's tap-outside / Esc dismisses the whole editor.
///
/// Pure presentation over a `TaskEditorModel`: every field binds to the model,
/// every action routes through it. The host owns the floating window/overlay,
/// the singleton rule, and (on macOS) window resizing; this view owns the
/// content, the quick→full grow animation, and the child-popup routing.
///
/// `onAddAttachment` is the one host seam (the platform-specific image/file
/// picker).
public struct TaskEditorView: View {
    @Bindable public var model: TaskEditorModel
    public var onDismiss: () -> Void
    public var onAddAttachment: (() -> Void)?

    /// Which in-card popup is showing. `.main` is the compact card; the others
    /// replace it and return on Back.
    private enum DetailRoute { case main, schedule, attachments, journal }
    @State private var route: DetailRoute = .main

    /// The card's editable fields bind focus to external `@FocusState` so the
    /// host owns first responder across relayouts. (The wrap card no longer
    /// swaps subtrees — see `WrapToContentThenScroll` / issue #32 — so this is
    /// no longer load-bearing for surviving a candidate swap, but keeping focus
    /// host-owned stays correct and lets the drill-in reset below manage it.)
    private enum EditorField { case title, notes }
    @FocusState private var focusedField: EditorField?

    // The tag row's inline-edit state lives here, on the host, so the drill-in
    // reset (`.onChange(of: route)` below) can collapse the field when the user
    // navigates into a child and back — the hoist widens the state's lifetime
    // past the card, which the reset then scopes back. (Pre-#32 the hoist also
    // aimed to survive a `ViewThatFits` swap; that swap is now eliminated.)
    @State private var isTagEditing = false
    @State private var tagDraft = ""
    @FocusState private var tagFieldFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion
    private var reduceMotion: Bool { overrideReduceMotion ?? systemReduceMotion }

    public init(
        model: TaskEditorModel,
        onDismiss: @escaping () -> Void,
        onAddAttachment: (() -> Void)? = nil
    ) {
        self.model = model
        self.onDismiss = onDismiss
        self.onAddAttachment = onAddAttachment
    }

    public var body: some View {
        Group {
            switch model.mode {
            case .quick: quickBody
            case .full: fullBody
            }
        }
    }

    // MARK: - Quick mode

    private var quickBody: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.m) {
            QuickCaptureFieldView(text: $model.captureText, onSubmit: submitQuick)

            let parsed = QuickCaptureParser.parse(model.captureText)
            if !parsed.tags.isEmpty || parsed.dateToken != nil {
                HStack(spacing: LillistSpacing.xs + 2) {
                    ForEach(parsed.tags, id: \.self) { TagChipView(name: $0) }
                    if let token = parsed.dateToken {
                        Label(token, systemImage: "calendar")
                            .font(LillistTypography.caption)
                            .foregroundStyle(LillistColor.textMuted)
                    }
                }
            }

            HStack(spacing: LillistSpacing.s) {
                Button {
                    expand()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(LillistTypography.title3)
                        .foregroundStyle(LillistColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "More options", bundle: .module))
                .accessibilityIdentifier("ExpandToFullEditorButton")

                Spacer(minLength: 0)

                Button(action: submitQuick) {
                    Text("Add", bundle: .module)
                }
                .buttonStyle(.rainbow(.lavender, size: .sm))
                .disabled(!model.isQuickCommittable)
                .accessibilityIdentifier("QuickCaptureAddButton")
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: LillistSizing.editorQuickMaxWidth)
        .glassSurface(.panel, in: RoundedRectangle(cornerRadius: LillistRadius.l))
    }

    // MARK: - Full mode (the compact detail card + child popups)

    private var fullBody: some View {
        Group {
            switch route {
            case .main: mainCard
            case .schedule: scheduleChild
            case .attachments: attachmentsChild
            case .journal: journalChild
            }
        }
        .frame(maxWidth: LillistSizing.editorCardMaxWidth)
        .glassSurface(.panel, in: RoundedRectangle(cornerRadius: LillistRadius.l))
        .task(id: textEditKey) {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await model.saveTextNow()
        }
        .onChange(of: scalarKey) { _, _ in
            Task { await model.saveScalarsNow() }
        }
        // The tag row's inline-edit state is hoisted to this view (see the
        // decls above). `route` is `@State` on this same view, so drilling into
        // a child and returning re-evaluates `body` without destroying our
        // identity — an open tag edit would otherwise survive the round-trip and
        // re-present itself, focused and holding a stale draft, on Back. Drilling
        // in is a deliberate context switch, so collapse the field and drop the
        // draft when we leave the main card (the same discard the tap-away
        // contract makes; the return to `.main` then shows the collapsed pill).
        .onChange(of: route) { _, newRoute in
            if newRoute != .main {
                isTagEditing = false
                tagDraft = ""
            }
        }
        .animation(reduceMotion ? nil : LillistMotion.squish(LillistMotion.fast), value: route)
    }

    // MARK: - Main card

    /// The detail card wraps its content (like Quick Capture) and only scrolls
    /// when the content genuinely overflows the offered height, so the
    /// header/title is never clipped off the centered overlay. Shares the
    /// `wrapToContentThenScroll` valve with the drill-in children; the main
    /// card fits the whole overlay (no height cap).
    private var mainCard: some View {
        wrapToContentThenScroll { mainCardContent }
    }

    @ViewBuilder
    private var mainCardContent: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.l) {
            header
            descriptionField
            TagAssignmentField(
                tagNames: model.displayedTagNames,
                isEditing: $isTagEditing,
                draftName: $tagDraft,
                fieldFocused: $tagFieldFocused,
                onAdd: { name in Task { await model.addTag(name: name) } },
                onRemove: { name in Task { await model.removeTag(named: name) } }
            )
            VStack(alignment: .leading, spacing: LillistSpacing.s) {
                scheduleRow
                attachmentsRow
                journalRow
            }
            captureFooter
        }
        .padding(LillistSpacing.l)
    }

    /// Status glyph + inline title, with the pin toggle pinned top-trailing.
    private var header: some View {
        HStack(spacing: LillistSpacing.s) {
            StatusIndicatorView(
                status: model.status,
                onClick: { Task { await model.setStatus(StatusCycler.nextOnClick(from: model.status)) } },
                onSetStatus: { s in Task { await model.setStatus(s) } }
            )
            TextField(
                text: $model.title,
                prompt: Text("Title", bundle: .module),
                axis: .vertical
            ) {
                Text("Title", bundle: .module)
            }
            .textFieldStyle(.plain)
            .font(LillistTypography.title3)
            // Match TaskRowLabel's closed treatment. Strikethrough only renders
            // on static Text, not an editable field, so closed state reads
            // through the muted colour alone (the field stays editable).
            .foregroundStyle(model.status == .closed ? LillistColor.textFaint : LillistColor.textStrong)
            .focused($focusedField, equals: .title)
            .accessibilityIdentifier("EditorTitleField")

            pinButton
        }
    }

    private var pinButton: some View {
        Button {
            model.isPinned.toggle()
        } label: {
            Image(systemName: model.isPinned ? "pin.fill" : "pin")
                .font(LillistTypography.title3)
                .foregroundStyle(model.isPinned ? RainbowPalette.scriptPurple.base : LillistColor.textFaint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPinned
            ? String(localized: "Unpin task", bundle: .module)
            : String(localized: "Pin task", bundle: .module))
        .accessibilityIdentifier("EditorPinButton")
    }

    /// The content-hugging notes box. iOS uses a vertical-axis `TextField`;
    /// macOS uses a bounded `TextEditor` so **Return inserts a newline** rather
    /// than submitting (a vertical-axis `TextField` routes Return to submit on
    /// AppKit — issue #29), with an invisible sizer preserving the same hug.
    @ViewBuilder
    private var descriptionField: some View {
        #if os(macOS)
        macNotesEditor
        #else
        // iOS: a vertical-axis `TextField` (matching the title) so the card
        // wraps its description rather than reserving a fixed tall box —
        // `.lineLimit(2...8)` grows it from two lines with the text and scrolls
        // in place past eight, keeping the card compact.
        TextField(
            text: $model.notes,
            prompt: Text("Add a description…", bundle: .module),
            axis: .vertical
        ) {
            Text("Add a description…", bundle: .module)
        }
        .textFieldStyle(.plain)
        .font(LillistTypography.body)
        .foregroundStyle(LillistColor.textBody)
        .lineLimit(2...8)
        .focused($focusedField, equals: .notes)
        .padding(LillistSpacing.s)
        .background {
            RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                .fill(.rainbowWell)
        }
        .accessibilityIdentifier("EditorNotesField")
        #endif
    }

    #if os(macOS)
    /// Horizontal inset AppKit's `NSTextView` (backing `TextEditor`) applies
    /// around its text; the invisible sizer and the placeholder match it so
    /// they wrap at the same width as the live editor. Tunable if the box
    /// mis-hugs on macOS (a wider sizer under-counts lines and clips).
    private static let macNotesTextInset: CGFloat = 5
    /// ~2 lines of body text — the iOS field's `.lineLimit(2...8)` floor.
    private static let macNotesMinHeight: CGFloat = 44

    /// The string the invisible sizer measures. SwiftUI `Text` drops a trailing
    /// newline from its measured height, so a note ending in Return (or a blank
    /// last line) would leave the `TextEditor`'s caret on an uncounted line and
    /// clip it. Append a zero-width space so the final line is always counted;
    /// the sizer is `.clear`, so it's invisible either way.
    private var macNotesSizerText: String {
        model.notes.isEmpty ? " " : model.notes + "\u{200B}"
    }

    /// macOS notes field: a bounded `TextEditor` (Return → newline, #29) whose
    /// height is driven by an **invisible `Text` sizer** so the box still hugs
    /// its content like the iOS field (#22), capped at `editorNotesMaxHeight`.
    ///
    /// The sizer is the base and the `TextEditor` is an `.overlay` on it — so
    /// the sizer's natural text height drives the frame and the (greedy)
    /// `TextEditor` merely fills it. A plain `ZStack` would instead let the
    /// greedy editor drive the height and defeat the hug (a fixed tall box).
    private var macNotesEditor: some View {
        Text(macNotesSizerText)
            .font(LillistTypography.body)
            // `.foregroundStyle(.clear)` only hides the sizer visually — a `Text`
            // with content is still an AX element, so hide it or VoiceOver reads
            // the note twice (once here, once from the live `TextEditor`).
            .foregroundStyle(.clear)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.macNotesTextInset)
            .frame(
                minHeight: Self.macNotesMinHeight,
                maxHeight: LillistSizing.editorNotesMaxHeight,
                alignment: .topLeading
            )
            .overlay(alignment: .topLeading) {
                TextEditor(text: $model.notes)
                    .font(LillistTypography.body)
                    .foregroundStyle(LillistColor.textBody)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("EditorNotesField")
                    .overlay(alignment: .topLeading) {
                        if model.notes.isEmpty {
                            Text("Add a description…", bundle: .module)
                                .font(LillistTypography.body)
                                .foregroundStyle(LillistColor.textFaint)
                                .padding(.horizontal, Self.macNotesTextInset)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .padding(LillistSpacing.s)
            .background {
                RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                    .fill(.rainbowWell)
            }
    }
    #endif

    // MARK: - Summary rows

    private var scheduleRow: some View {
        drillRow(
            icon: "calendar",
            text: DueLineFormatter.string(
                deadline: model.deadline,
                deadlineHasTime: model.deadlineHasTime,
                start: model.start,
                startHasTime: model.startHasTime,
                recurrence: model.recurrence.summary
            ),
            muted: model.deadline == nil && model.start == nil,
            action: .edit,
            identifier: "EditorScheduleRow"
        ) { route = .schedule }
    }

    private var attachmentsRow: some View {
        drillRow(
            icon: "paperclip",
            text: attachmentSummary,
            muted: model.attachments.isEmpty,
            action: .add,
            identifier: "EditorAttachmentsRow"
        ) { route = .attachments }
    }

    private var journalRow: some View {
        drillRow(
            icon: "book.closed",
            text: journalSummary,
            muted: model.journal.isEmpty,
            action: .drill,
            identifier: "EditorJournalRow"
        ) { route = .journal }
    }

    private enum RowAction { case edit, add, drill }

    @ViewBuilder
    private func drillRow(
        icon: String,
        text: String,
        muted: Bool,
        action: RowAction,
        identifier: String,
        open: @escaping () -> Void
    ) -> some View {
        Button(action: open) {
            HStack(spacing: LillistSpacing.s) {
                Image(systemName: icon)
                    .font(LillistTypography.body)
                    .foregroundStyle(LillistColor.textMuted)
                    .frame(width: 22)
                Text(text)
                    .font(LillistTypography.body)
                    .foregroundStyle(muted ? LillistColor.textFaint : LillistColor.textBody)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: LillistSpacing.s)
                switch action {
                case .edit: actionPill("Edit")
                case .add: actionPill("Add")
                case .drill:
                    Image(systemName: "chevron.right")
                        .font(LillistTypography.caption)
                        .foregroundStyle(LillistColor.textFaint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func actionPill(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module)
            .font(LillistTypography.caption)
            .textCase(.uppercase)
            .foregroundStyle(RainbowPalette.scriptPurple.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                Capsule().strokeBorder(RainbowPalette.scriptPurple.base.opacity(0.5), lineWidth: 1)
            )
    }

    private var attachmentSummary: String {
        let n = model.attachments.count
        if n == 0 { return String(localized: "No attachments", bundle: .module) }
        return n == 1
            ? String(localized: "1 attachment", bundle: .module)
            : String(localized: "\(n) attachments", bundle: .module)
    }

    private var journalSummary: String {
        let n = model.journal.count
        if n == 0 { return String(localized: "No journal entries yet.", bundle: .module) }
        return n == 1
            ? String(localized: "1 journal entry", bundle: .module)
            : String(localized: "\(n) journal entries", bundle: .module)
    }

    /// New-capture-only commit affordance. Existing tasks live-save every
    /// field and dismiss on tap-outside/Esc, so they need no footer buttons;
    /// a `.capture` draft still needs an explicit "Add" (a bare dismiss can't
    /// persist a draft that never performed a promoting op).
    @ViewBuilder
    private var captureFooter: some View {
        if model.presentation == .capture {
            VStack(alignment: .leading, spacing: LillistSpacing.s) {
                if let warning = model.lastCommitWarning {
                    Label {
                        Text("Saved, but couldn't apply: \(warning)", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(LillistTypography.caption)
                    .foregroundStyle(RainbowPalette.cautionAmber.ink)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button(action: submitFull) {
                        Text("Add", bundle: .module)
                    }
                    .buttonStyle(.rainbow(.lavender, size: .sm))
                    .disabled(!model.isCommittable)
                    .accessibilityIdentifier("EditorAddButton")
                }
            }
        }
    }

    // MARK: - Child popups

    private func childHeader(_ title: LocalizedStringKey, onBack: @escaping () -> Void) -> some View {
        ZStack {
            Text(title, bundle: .module)
                .font(LillistTypography.headline)
                .foregroundStyle(LillistColor.textStrong)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Back", bundle: .module)
                    }
                    .font(LillistTypography.body)
                    .foregroundStyle(LillistColor.textBody)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("EditorChildBackButton")
                Spacer(minLength: 0)
            }
        }
        .padding(LillistSpacing.l)
    }

    /// Schedule child — dates + recurrence in one `Form`. Dates live-save via
    /// the outer `scalarKey` observer; the recurrence rule is committed on Back
    /// (`commitRecurrence` auto-promotes a draft when a rule is set).
    private var scheduleChild: some View {
        VStack(spacing: 0) {
            childHeader("Schedule") {
                Task { try? await model.commitRecurrence() }
                route = .main
            }
            Form {
                Section {
                    dateControls(label: "Deadline", date: $model.deadline, hasTime: $model.deadlineHasTime)
                }
                Section {
                    dateControls(label: "Start", date: $model.start, hasTime: $model.startHasTime)
                }
                RecurrenceEditorView(viewModel: $model.recurrence).formContent
            }
            .frame(maxHeight: LillistSizing.editorChildMaxHeight)
        }
    }

    @ViewBuilder
    private func dateControls(label: LocalizedStringKey, date: Binding<Date?>, hasTime: Binding<Bool>) -> some View {
        let isSet = Binding(
            get: { date.wrappedValue != nil },
            set: { date.wrappedValue = $0 ? (date.wrappedValue ?? Date()) : nil }
        )
        Toggle(isOn: isSet) {
            Text(label, bundle: .module)
        }
        if let unwrapped = date.wrappedValue {
            let bound = Binding(get: { unwrapped }, set: { date.wrappedValue = $0 })
            DatePicker(
                selection: bound,
                displayedComponents: hasTime.wrappedValue ? [.date, .hourAndMinute] : [.date]
            ) {
                Text("When", bundle: .module)
            }
            Toggle(isOn: hasTime) {
                Text("Include time", bundle: .module)
            }
        }
    }

    private var attachmentsChild: some View {
        VStack(spacing: 0) {
            childHeader("Attachments") { route = .main }
            wrapToContentThenScroll(maxHeight: LillistSizing.editorChildMaxHeight) {
                EditorAttachmentsSection(
                    attachments: model.attachments,
                    onAddTapped: onAddAttachment,
                    onDelete: { id in Task { await model.deleteAttachment(id: id) } }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LillistSpacing.l)
            }
        }
    }

    private var journalChild: some View {
        VStack(spacing: 0) {
            childHeader("Journal") { route = .main }
            wrapToContentThenScroll(maxHeight: LillistSizing.editorChildMaxHeight) {
                EditorJournalSection(entries: model.journal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LillistSpacing.l)
            }
        }
    }

    /// Wrap content so it hugs its size and scrolls only on genuine overflow,
    /// in a **single, non-swapping subtree** (`WrapToContentThenScroll`).
    /// `maxHeight` bounds the scroll viewport — drill-in children pass
    /// `editorChildMaxHeight` so a nearly-empty child hugs its content and a
    /// long one scrolls; the main card passes `nil` to fit the whole overlay.
    private func wrapToContentThenScroll<Content: View>(
        maxHeight: CGFloat? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        WrapToContentThenScroll(maxHeight: maxHeight, content: content())
    }

    // MARK: - Actions

    private func submitQuick() {
        Task {
            guard (try? await model.commitQuickCapture()) != nil else { return }
            onDismiss()
        }
    }

    /// Commit a full-mode capture draft and close.
    private func submitFull() {
        Task {
            guard (try? await model.commitDraft()) != nil else { return }
            onDismiss()
        }
    }

    private func expand() {
        if reduceMotion {
            model.expandToFull()
        } else {
            withAnimation(LillistMotion.squish(LillistMotion.slow)) {
                model.expandToFull()
            }
        }
    }

    // MARK: - Helpers

    /// Combined debounce key — restarts the `.task` when title or notes change.
    private var textEditKey: String { "\(model.title)\u{1}\(model.notes)" }

    private struct ScalarKey: Equatable {
        var start: Date?
        var startHasTime: Bool
        var deadline: Date?
        var deadlineHasTime: Bool
        var isPinned: Bool
    }

    private var scalarKey: ScalarKey {
        ScalarKey(
            start: model.start,
            startHasTime: model.startHasTime,
            deadline: model.deadline,
            deadlineHasTime: model.deadlineHasTime,
            isPinned: model.isPinned
        )
    }
}

/// Wrap-then-scroll in a **single, non-swapping subtree**: the content hugs its
/// size when it fits the offered height and scrolls in place only on genuine
/// overflow — without a `ViewThatFits` candidate swap.
///
/// The former `ViewThatFits(in: .vertical) { inner; ScrollView { inner } }`
/// swapped between two structurally-distinct subtrees when a keyboard/content
/// change flipped the fit decision, which *tore down and rebuilt* any focused
/// field inside `inner`. That collapsed the inline "+ Tag" field mid-edit and
/// dropped its keyboard — a failure no hoisted value state could fully survive,
/// because SwiftUI mutates `@FocusState` on the teardown (issue #32).
///
/// A bare `ScrollView` is vertically greedy, so cap its height to the content's
/// own measured ideal height (bounded by `maxHeight`): the parent's proposal
/// then constrains it further when the keyboard shrinks the offer, engaging the
/// scroll *without* recreating the subtree. Wrap-to-content (#22) is preserved.
private struct WrapToContentThenScroll<Content: View>: View {
    let maxHeight: CGFloat?
    let content: Content

    /// The content's ideal (unclipped) height, measured inside the scroll view
    /// where it's proposed an unbounded vertical extent. `0` until the first
    /// `onGeometryChange` lands, so `cappedHeight` seeds a bounded estimate for
    /// that pass rather than letting the scroll view paint greedily.
    @State private var contentHeight: CGFloat = 0

    /// First-pass height estimate for the uncapped main card, used only until
    /// `onGeometryChange` reports the real content height. A typical detail-card
    /// height, so the initial frame is close to the settled size (a bare `nil`
    /// here would paint at the full offered height, then snap down). Computed,
    /// not stored: a generic type can't hold a `static` stored property.
    private static var firstPassCardHeight: CGFloat { 340 }

    var body: some View {
        ScrollView(.vertical) {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(maxHeight: cappedHeight)
    }

    /// Cap the greedy scroll view to the content's ideal height (so it hugs),
    /// bounded by `maxHeight`.
    ///
    /// Before the first measurement lands (`onGeometryChange` reports in a later
    /// transaction), fall back to a *bounded* estimate — never `nil`. A `nil`
    /// cap lets the greedy scroll view paint at the full offered height for one
    /// pass and then snap to the content height; that overshoot is visible and
    /// recurs on every drill-in → Back, because the `route` switch re-instantiates
    /// this view with `contentHeight` reset to 0, overlapping the card's
    /// transition. Drill-in children estimate with their own `maxHeight` cap
    /// (their content trends toward it); the uncapped main card with a typical
    /// card height. The measured value takes over on the next pass either way.
    private var cappedHeight: CGFloat? {
        guard contentHeight > 0 else { return maxHeight ?? Self.firstPassCardHeight }
        guard let maxHeight else { return contentHeight }
        return min(contentHeight, maxHeight)
    }
}

/// The quick-mode capture field — the sunken `rainbowWell` look from the
/// original Quick Capture dialog, bound to the model's `captureText`.
private struct QuickCaptureFieldView: View {
    @Binding var text: String
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(
            text: $text,
            prompt: Text("Capture a task…  #tag ^date", bundle: .module)
        ) {
            Text("New task", bundle: .module)
        }
        .textFieldStyle(.plain)
        .font(LillistTypography.quickCaptureField)
        .foregroundStyle(LillistColor.textStrong)
        .submitLabel(.done)
        .focused($focused)
        .accessibilityIdentifier("QuickCaptureField")
        .onSubmit { focused = false; onSubmit() }
        .onAppear { focused = true }
        .padding(.horizontal, LillistSpacing.m)
        .padding(.vertical, LillistSpacing.s + 2)
        .background {
            RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                .fill(focused ? AnyShapeStyle(LillistColor.card) : AnyShapeStyle(.rainbowWell))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                .strokeBorder(
                    focused ? RainbowPalette.focusBlue.base.opacity(0.35) : LillistColor.borderHair,
                    lineWidth: focused ? 2 : 1
                )
        }
    }
}
