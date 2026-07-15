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

    /// The card is wrapped in a `ViewThatFits` valve whose two candidates are
    /// structurally-distinct copies of the editable fields. Binding focus to
    /// external `@FocusState` lets it re-apply to the surviving candidate when a
    /// content/keyboard change flips ViewThatFits mid-edit, so first responder
    /// (and the keyboard) isn't dropped on the swap.
    private enum EditorField { case title, notes }
    @FocusState private var focusedField: EditorField?

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
        .animation(reduceMotion ? nil : LillistMotion.squish(LillistMotion.fast), value: route)
    }

    // MARK: - Main card

    /// The detail card wraps its content (like Quick Capture) and only scrolls
    /// when the content genuinely overflows the offered height. `ViewThatFits`
    /// picks the plain, self-sizing layout first and falls back to the scrolling
    /// copy at large Dynamic Type / long notes, so the header/title is never
    /// clipped off the centered overlay.
    private var mainCard: some View {
        ViewThatFits(in: .vertical) {
            mainCardContent
            ScrollView { mainCardContent }
        }
    }

    @ViewBuilder
    private var mainCardContent: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.l) {
            header
            descriptionField
            TagAssignmentField(
                tagNames: model.displayedTagNames,
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

    /// A content-hugging notes field (a vertical-axis `TextField`, matching the
    /// title) so the card wraps its description rather than reserving a fixed
    /// tall box: it grows from two lines with the text and scrolls in place once
    /// it reaches `editorNotesMaxHeight`, keeping the card compact.
    private var descriptionField: some View {
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
            boundedChild {
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
            boundedChild {
                EditorJournalSection(entries: model.journal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LillistSpacing.l)
            }
        }
    }

    /// Wrap a drill-in child's content so it grows to fit its content and
    /// scrolls only once it exceeds the child height cap — the same
    /// wrap-then-scroll behavior as the main card, so a nearly-empty child
    /// hugs its content (no dead slack) and a long one never fills the screen.
    @ViewBuilder
    private func boundedChild<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let inner = content()
        ViewThatFits(in: .vertical) {
            inner
            ScrollView { inner }
        }
        .frame(maxHeight: LillistSizing.editorChildMaxHeight)
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
