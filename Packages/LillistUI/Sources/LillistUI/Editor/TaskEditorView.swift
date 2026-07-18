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
    /// swaps subtrees — see `MeasuredGlassCard` / issue #32 — so this is no
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

    // Last measured content height per route, kept on the host (which survives a
    // drill-in → Back) so a card rebuilt on return seeds its own height instead
    // of resetting to the bounded first-pass and popping to size a frame later.
    // First visit to a route has no entry yet, so that card settles once, masked
    // by the open/drill-in animation.
    @State private var cardHeights: [DetailRoute: CGFloat] = [:]

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
        // The glass panel is applied ONCE here, to the outer Group, not per card,
        // so it keeps a stable identity across a route change: only the card
        // content crossfades inside one steady panel, rather than two translucent
        // panels overlapping. Each card supplies its own *height* (bounded
        // first-pass until measured, seeded per route from `cardHeights`), and the
        // Group — hence the panel — animates smoothly to it. Safe to share now
        // that the card is bounded, not greedy, so the panel never flashes the
        // full offer.
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

    /// The detail card wraps its content (like Quick Capture) and only scrolls
    /// when the content genuinely overflows the offered height, so the
    /// header/title is never clipped off the centered overlay. Shares the
    /// `MeasuredGlassCard` chrome with the attachments/journal children; the main
    /// card passes no `maxHeight`, fitting the whole overlay.
    private var mainCard: some View {
        MeasuredGlassCard(
            initialHeight: cardHeights[.main],
            // Only remember the *collapsed* height. `onMeasured` also fires while
            // the inline tag field is open (which grows the card), but the field is
            // always collapsed on Back (the `.onChange(of: route)` reset above), so
            // a height captured with it open would over-seed the rebuilt card and
            // flash a blank gap below the content for a frame. Skip those. (#35)
            onMeasured: { if Self.shouldRememberMainCardHeight(isTagEditing: isTagEditing) { cardHeights[.main] = $0 } }
        ) { mainCardContent }
    }

    /// Whether a freshly measured `.main` card height should be remembered as the
    /// seed for the card rebuilt on a drill-in → Back round-trip. Only the
    /// collapsed height is valid: the inline tag field grows the card while open,
    /// and it is always collapsed on Back (the `.onChange(of: route)` reset), so a
    /// height captured while editing would over-seed the rebuilt card. Pinned by
    /// `MainCardHeightSeedTests`; `internal` for `@testable` reach. (#35)
    nonisolated static func shouldRememberMainCardHeight(isTagEditing: Bool) -> Bool {
        !isTagEditing
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
    /// Approximate horizontal inset of `TextEditor`'s text start on macOS
    /// (`NSTextView`'s `lineFragmentPadding` ≈ 5pt), used to left-align the
    /// placeholder with where the caret will sit.
    ///
    /// The `macNotes*Inset`/`Slack` constants below **estimate undocumented
    /// `NSTextView` metrics** (`lineFragmentPadding` + `textContainerInset`),
    /// whose exact total isn't public. They're biased to over-count so the box
    /// never clips, and were set against **macOS 26 / iOS 26**. There is no
    /// *pixel-level* coverage — macOS glass/editor snapshots are
    /// `XCTSkip`-quarantined, so if a future OS changes those insets past the
    /// slack the field could clip; verify/tune on-device and re-check whenever the
    /// deployment target moves. `MacNotesSizerMetricsTests` pins the over-count
    /// *contract* (sizer inset > editor inset, positive slack) but not the real
    /// hug — hence these are `internal`, not `private` (#36).
    nonisolated static let macNotesTextInset: CGFloat = 5
    /// Top inset estimating `NSTextView`'s vertical `textContainerInset`, so the
    /// empty-state placeholder's first line lands on the caret's baseline instead
    /// of a few points above it (see the metrics caveat on `macNotesTextInset`).
    nonisolated static let macNotesTopInset: CGFloat = 5
    /// Horizontal inset for the invisible **sizer** — deliberately *larger* than
    /// the editor's real text inset. The sizer drives the box height by wrapping
    /// the note at its own width, so if it wrapped *wider* than the live editor
    /// it would count too few lines and the editor would clip its last line
    /// against the height cap. `TextEditor` also applies a `textContainerInset`
    /// beyond `lineFragmentPadding`, and the exact total isn't publicly known, so
    /// bias the sizer narrower than any plausible editor width: it can then only
    /// *over*-count (a little bottom slack), never clip. The macOS box has no
    /// snapshot path — verify the hug on-device against a note whose lines wrap
    /// right at the box width, and tune here if needed.
    nonisolated static let macNotesSizerInset: CGFloat = 12
    /// Vertical slack the sizer adds beyond the raw text height. `NSTextView`
    /// insets its text vertically (`textContainerInset`, top **and** bottom) on
    /// top of the wrapped-line height, and a note of short lines (no horizontal
    /// wrap difference) gets no slack from `macNotesSizerInset` — so without this
    /// the box resolves to ~the raw text height and the editor clips its last
    /// line. Add a small over-estimate of that vertical inset (top+bottom); a bit
    /// of bottom breathing room is harmless, a shortfall clips. Verify on-device.
    nonisolated static let macNotesVerticalSlack: CGFloat = 8
    /// ~2 lines of body text — the iOS field's `.lineLimit(2...8)` floor.
    private static let macNotesMinHeight: CGFloat = 44

    /// The string the invisible sizer measures. SwiftUI `Text` drops a trailing
    /// newline from its measured height, so a note ending in Return (or a blank
    /// last line) would leave the `TextEditor`'s caret on an uncounted line and
    /// clip it. Append a zero-width space so the final line is always counted;
    /// the sizer is `.clear`, so it's invisible either way. Static so
    /// `MacNotesSizerMetricsTests` can pin the trailing-newline rule (#36).
    nonisolated static func macNotesSizerText(for notes: String) -> String {
        notes.isEmpty ? " " : notes + "\u{200B}"
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
        Text(Self.macNotesSizerText(for: model.notes))
            .font(LillistTypography.body)
            // `.foregroundStyle(.clear)` only hides the sizer visually — a `Text`
            // with content is still an AX element, so hide it or VoiceOver reads
            // the note twice (once here, once from the live `TextEditor`).
            .foregroundStyle(.clear)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.macNotesSizerInset)
            .padding(.vertical, Self.macNotesVerticalSlack)
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
                                .padding(.top, Self.macNotesTopInset)
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
        MeasuredGlassCard(
            maxHeight: LillistSizing.editorChildMaxHeight,
            initialHeight: cardHeights[.attachments],
            onMeasured: { cardHeights[.attachments] = $0 }
        ) {
            childHeader("Attachments") { route = .main }
        } content: {
            EditorAttachmentsSection(
                attachments: model.attachments,
                onAddTapped: onAddAttachment,
                onDelete: { id in Task { await model.deleteAttachment(id: id) } }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LillistSpacing.l)
        }
    }

    private var journalChild: some View {
        MeasuredGlassCard(
            maxHeight: LillistSizing.editorChildMaxHeight,
            initialHeight: cardHeights[.journal],
            onMeasured: { cardHeights[.journal] = $0 }
        ) {
            childHeader("Journal") { route = .main }
        } content: {
            EditorJournalSection(entries: model.journal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LillistSpacing.l)
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

/// A full-editor card body: hugs its scrolling content and scrolls only on
/// overflow. The glass panel is *not* applied here — it lives on the shared
/// `fullBody` Group (`.editorGlassPanel()`), so a route change crossfades content
/// inside one steady panel rather than overlapping two.
///
/// A bare `ScrollView` is vertically greedy, so its height is capped to the
/// content's own measured ideal height (bounded by `maxHeight`): the parent's
/// proposal then engages the scroll when the keyboard shrinks the offer, without
/// recreating the subtree (so a focused "+ Tag" field isn't torn down — issue
/// #32). `header` (a child popup's Back bar) sits above the scroll area; the main
/// card passes none. Wrap-to-content (#22) is preserved.
///
/// Because `content` is always inside this scroll view (the synchronous
/// `ViewThatFits` valve used a non-scrolling candidate when the card fit), the
/// iOS notes `TextField`'s own in-place scroll (past 8 lines) nests inside it.
/// `.scrollBounceBehavior(.basedOnSize)` keeps this outer scroll passive in the
/// *fitting* case (contentSize == bounds), so a drag reaches the field. In the
/// *overflowing* case (fat notes with the keyboard up), this outer scroll is
/// active, so a drag begun inside a >8-line note is genuinely ambiguous — it may
/// pan the card rather than scroll the note's own overflow. There's no clean
/// declarative resolution short of the field-tearing valve or an overlay-level
/// scroll; flagged for on-device confirmation.
///
/// The measured cap arrives asynchronously (`onGeometryChange` reports in a
/// later transaction), so for the first frame — on open, quick→full expand, and
/// each drill-in that rebuilds the card — the height is unknown. Rather than
/// paint greedily (the panel filling the full offer, then snapping down) or
/// blank the card (an invisible-but-hittable panel that pops in), cap that first
/// frame to a *bounded* first-pass height: the card shows its top, in a
/// reasonably-sized panel, then resizes to hug once measured — a small settle
/// masked by the entry/route animation, never a full-offer flash or a blank pop.
///
/// Known limitations of the async cap, both accepted costs of the single,
/// non-swapping subtree that keeps the focused field alive (#32):
///  - It trails content *growth* by a frame. On the main card (no `maxHeight`, so
///    the cap equals the content height), adding a notes line while typing grows
///    the content one layout pass before `onGeometryChange` raises the cap, so
///    the scroll view is momentarily a line short and auto-scrolls to keep the
///    caret visible — a one-frame micro-jump the synchronous `ViewThatFits` valve
///    didn't have.
///  - `onMeasured` writes the host's `cardHeights` `@State` from the geometry
///    callback, so a genuine content-height change re-evaluates the whole
///    `TaskEditorView` body, not just this subtree. It's a no-op re-render when
///    the height is unchanged (e.g. a seeded card re-measuring the same value),
///    and content-height changes are infrequent, so this is cheap in practice.
/// Removing either would mean the field-tearing valve or moving the scroll to the
/// overlay. Flagged for on-device confirmation of whether the settle is perceptible.
private struct MeasuredGlassCard<Header: View, Content: View>: View {
    private let maxHeight: CGFloat?
    private let onMeasured: (CGFloat) -> Void
    private let header: Header
    private let content: Content

    /// The content's ideal (unclipped) height, measured inside the scroll view
    /// where it's proposed an unbounded vertical extent. Seeded from the host's
    /// remembered height (so a rebuilt card starts sized), else `0` — when
    /// `cappedHeight` uses the bounded first-pass height until `onGeometryChange`
    /// lands.
    @State private var contentHeight: CGFloat

    init(
        maxHeight: CGFloat? = nil,
        initialHeight: CGFloat?,
        onMeasured: @escaping (CGFloat) -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.maxHeight = maxHeight
        self.onMeasured = onMeasured
        self.header = header()
        self.content = content()
        self._contentHeight = State(initialValue: initialHeight ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
                        contentHeight = newHeight
                        onMeasured(newHeight)
                    }
            }
            .frame(maxHeight: cappedHeight)
            // Don't bounce/scroll when the content fits: the iOS notes field is a
            // vertical-axis `TextField` that scrolls its own overflow in place, so
            // when the card fits (this scroll view's contentSize == bounds) this
            // outer scroll must stay passive and let a drag inside a long note
            // reach the field, not pan the card.
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Cap the greedy scroll view to the content's ideal height (so it hugs),
    /// bounded by `maxHeight`. Before the first measurement, a bounded first-pass
    /// height (also bounded by `maxHeight`) — never `nil` (greedy) — so the card
    /// is visible but not full-offer while it measures.
    private var cappedHeight: CGFloat? {
        MeasuredCardSizing.cappedHeight(content: contentHeight, maxHeight: maxHeight)
    }
}

/// Pure sizing math shared by every `MeasuredGlassCard`, factored out of the
/// generic view so `MeasuredCardSizingTests` can pin the seeding contract without
/// a host render (the generic, `private` view is unreachable via `@testable`).
/// Being non-generic, it also lets `firstPassHeight` be a proper stored `let`. (#35)
enum MeasuredCardSizing {
    /// Bounded first-pass height until the content measures — enough to show the
    /// card's top (header + first rows) without filling the offer.
    static let firstPassHeight: CGFloat = 220

    /// The measured content height (or the first-pass fallback when unmeasured),
    /// clamped to `maxHeight` when the card is bounded. Never nil: a bounded card
    /// can only ever seed up to its cap, so a stale-tall seed can't gap the layout.
    static func cappedHeight(content: CGFloat, maxHeight: CGFloat?) -> CGFloat {
        let unbounded = content > 0 ? content : firstPassHeight
        guard let maxHeight else { return unbounded }
        return min(unbounded, maxHeight)
    }
}

extension MeasuredGlassCard where Header == EmptyView {
    /// A headerless card (the main detail card).
    init(
        maxHeight: CGFloat? = nil,
        initialHeight: CGFloat?,
        onMeasured: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            maxHeight: maxHeight, initialHeight: initialHeight,
            onMeasured: onMeasured, header: { EmptyView() }, content: content
        )
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
