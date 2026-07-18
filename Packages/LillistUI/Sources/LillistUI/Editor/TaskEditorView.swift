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
    /// host owns first responder across relayouts. (The card is one stable,
    /// self-sizing subtree that never swaps — issues #32/#38 — so this is no
    /// longer load-bearing for surviving a candidate swap, but keeping focus
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
            case .main: mainCardContent
            case .schedule: scheduleChild
            case .attachments: attachmentsChild
            case .journal: journalChild
            }
        }
        // The glass panel is applied ONCE here, to the outer Group, not per card,
        // so it keeps a stable identity across a route change: only the card
        // content crossfades inside one steady panel, rather than two translucent
        // panels overlapping. Each branch is a plain, hugging VStack that sizes
        // itself synchronously (issue #38), so the Group — hence the panel —
        // animates smoothly to each route's own height with no measurement pass
        // and no first-frame flash. The overlay's `editorScrollAndCenter` owns the
        // single scroll and centers/scrolls this whole panel.
        .editorGlassPanel()
        .task(id: textEditKey) {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await model.saveTextNow()
        }
        .onChange(of: scalarKey) { _, _ in
            Task { await model.saveScalarsNow() }
        }
        // The tag row's inline-edit state is hoisted to this view. `route` is
        // `@State` here, so drilling into a child and returning re-evaluates
        // `body` without destroying identity — an open tag edit would survive the
        // round-trip and re-present itself, focused and holding a stale draft, on
        // Back. Drilling in is a deliberate context switch, so collapse the field
        // and drop the draft when we leave the main card.
        .onChange(of: route) { _, newRoute in
            if newRoute != .main {
                isTagEditing = false
                tagDraft = ""
            }
        }
        .animation(reduceMotion ? nil : LillistMotion.squish(LillistMotion.fast), value: route)
    }

    // MARK: - Main card

    /// The detail card content — a plain, self-sizing VStack. It hugs its content
    /// synchronously (no measurement); the overlay's `editorScrollAndCenter` owns
    /// the single scroll and lifts/scrolls it when the keyboard shrinks the offer,
    /// so the header/title is never clipped off the centered overlay.
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
    /// macOS uses a self-measuring `NSTextView` (`MacNotesTextView`) so **Return
    /// inserts a newline** rather than submitting (a vertical-axis `TextField`
    /// routes Return to submit on AppKit — issue #29), while still hugging its
    /// content like the iOS field (#22, #36).
    @ViewBuilder
    private var descriptionField: some View {
        #if os(macOS)
        MacNotesTextView(
            text: $model.notes,
            isFocused: Binding(
                get: { focusedField == .notes },
                // Only ever clear `.notes` on resign — don't stomp a focus that
                // has already moved to another field (e.g. the title).
                set: { focusedField = $0 ? .notes : (focusedField == .notes ? nil : focusedField) }
            ),
            placeholder: String(localized: "Add a description…", bundle: .module)
        )
        .padding(LillistSpacing.s)
        .background {
            RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                .fill(.rainbowWell)
        }
        #else
        // iOS: a vertical-axis `TextField` (matching the title) so the card
        // wraps its description rather than reserving a fixed tall box.
        // `.lineLimit(2...)` grows it from two lines with the text and — crucially —
        // never scrolls in place: with no upper cap there is no inner scroll to
        // fight the overlay's single scroll, so a drag inside a long note scrolls
        // the whole card instead of being ambiguous (issue #34). The overlay
        // handles overflow.
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
        .lineLimit(2...)
        .focused($focusedField, equals: .notes)
        .padding(LillistSpacing.s)
        .background {
            RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                .fill(.rainbowWell)
        }
        .accessibilityIdentifier("EditorNotesField")
        #endif
    }

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
        // A `Form` bounded by `.frame(maxHeight:)` is not vertically greedy and
        // lays out synchronously, so — unlike the wrap cards — it needs no
        // measurement gate; it just carries the shared glass panel directly.
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
            EditorChildBody {
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
            EditorChildBody {
                EditorJournalSection(entries: model.journal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LillistSpacing.l)
            }
        }
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

private extension View {
    /// The full-editor card chrome — max width + the `.panel` glass surface.
    /// Applied once to the full-mode Group (see `fullBody`) so the panel keeps a
    /// stable identity across route changes. (Quick mode uses a different width.)
    func editorGlassPanel() -> some View {
        self
            .frame(maxWidth: LillistSizing.editorCardMaxWidth)
            .glassSurface(.panel, in: RoundedRectangle(cornerRadius: LillistRadius.l))
    }
}

/// A child popup's scrollable body (Attachments / Journal). The Back header is
/// pinned by the caller *above* this view; only the section content is governed
/// here.
///
/// Sizing is synchronous — no measurement, no `onGeometryChange`. The only choice
/// is who owns the scroll, and that depends on the host (issue #38):
///  - **`editorHasOuterScroll == true`** (the overlay's `editorScrollAndCenter`):
///    the section *hugs* its content and the overlay's single scroll handles any
///    overflow. No nested scroll.
///  - **`false`** (a scroll-less host — the macOS hotkey `NSPanel`, which sizes
///    itself to the editor's intrinsic height): the section self-bounds to
///    `editorChildMaxHeight` and scrolls internally, so a long list can't grow the
///    panel past the screen and clip. `.scrollBounceBehavior(.basedOnSize)` keeps
///    it passive until it actually overflows.
///
/// The glass panel is *not* applied here — it lives on the shared `fullBody` Group
/// (`.editorGlassPanel()`), so a route change crossfades content inside one steady
/// panel.
struct EditorChildBody<Content: View>: View {
    @Environment(\.editorHasOuterScroll) private var hasOuterScroll
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if hasOuterScroll {
            content
        } else {
            ScrollView(.vertical) { content }
                .frame(maxHeight: LillistSizing.editorChildMaxHeight)
                .scrollBounceBehavior(.basedOnSize)
        }
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
