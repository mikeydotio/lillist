import SwiftUI
import LillistCore

/// The unified task editor — one cross-platform presentation with two modes
/// (`quick` / `full`) that differ only in size and which sections show.
///
/// Pure presentation over a `TaskEditorModel`: every field binds to the model,
/// every action routes through it. The host owns the floating window/overlay,
/// the singleton rule, and (on macOS) window resizing; this view owns the
/// content and the in-place quick→full grow animation.
///
/// `onOpenSubtask` and `onAddAttachment` are the only host seams (genuinely
/// platform-specific: re-targeting the singleton, and the image/file picker).
public struct TaskEditorView: View {
    @Bindable public var model: TaskEditorModel
    public var onDismiss: () -> Void
    public var onOpenSubtask: ((UUID) -> Void)?
    public var onAddAttachment: (() -> Void)?

    @State private var showRecurrenceSheet = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion
    private var reduceMotion: Bool { overrideReduceMotion ?? systemReduceMotion }

    public init(
        model: TaskEditorModel,
        onDismiss: @escaping () -> Void,
        onOpenSubtask: ((UUID) -> Void)? = nil,
        onAddAttachment: (() -> Void)? = nil
    ) {
        self.model = model
        self.onDismiss = onDismiss
        self.onOpenSubtask = onOpenSubtask
        self.onAddAttachment = onAddAttachment
    }

    public var body: some View {
        Group {
            switch model.mode {
            case .quick: quickBody
            case .full: fullBody
            }
        }
        .sheet(isPresented: $showRecurrenceSheet) {
            recurrenceSheet
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
        .frame(maxWidth: 360)
        .glassSurface(.panel, in: RoundedRectangle(cornerRadius: LillistRadius.l))
    }

    // MARK: - Full mode

    private var fullBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LillistSpacing.l) {
                titleSection
                statusSection
                datesSection
                pinSection
                section("Tags") {
                    TagAssignmentField(
                        tagNames: model.displayedTagNames,
                        onAdd: { name in Task { await model.addTag(name: name) } },
                        onRemove: { name in Task { await model.removeTag(named: name) } }
                    )
                }
                recurrenceSection
                section("Reminders") {
                    ReminderEditorSection(
                        reminders: model.reminders,
                        defaultDate: model.deadline ?? model.start,
                        onAdd: { kind, offset, date in
                            Task { try? await model.addReminder(kind: kind, offsetMinutes: offset, fireDate: date) }
                        },
                        onDelete: { id in Task { await model.deleteReminder(id: id) } }
                    )
                }
                notesSection
                section("Subtasks") {
                    EditorSubtasksSection(
                        subtasks: model.subtasks,
                        onAdd: { title in Task { try? await model.addSubtask(title: title) } },
                        onOpen: onOpenSubtask
                    )
                }
                section("Journal") {
                    EditorJournalSection(
                        entries: model.journal,
                        onAddNote: { body in Task { try? await model.addJournalNote(body) } }
                    )
                }
                section("Attachments") {
                    EditorAttachmentsSection(
                        attachments: model.attachments,
                        onAddTapped: onAddAttachment,
                        onDelete: { id in Task { await model.deleteAttachment(id: id) } }
                    )
                }
                footer
            }
            .padding(LillistSpacing.l)
        }
        .frame(maxWidth: 560)
        .glassSurface(.panel, in: RoundedRectangle(cornerRadius: LillistRadius.l))
        .task(id: textEditKey) {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await model.saveTextNow()
        }
        .onChange(of: scalarKey) { _, _ in
            Task { await model.saveScalarsNow() }
        }
    }

    // MARK: - Full-mode sections

    private var titleSection: some View {
        TextField(
            text: $model.title,
            prompt: Text("Title", bundle: .module),
            axis: .vertical
        ) {
            Text("Title", bundle: .module)
        }
        .textFieldStyle(.plain)
        .font(LillistTypography.title3)
        .foregroundStyle(LillistColor.textStrong)
        .accessibilityIdentifier("EditorTitleField")
    }

    private var statusSection: some View {
        section("Status") {
            HStack(spacing: LillistSpacing.m) {
                StatusIndicatorView(
                    status: model.status,
                    onClick: { Task { await model.setStatus(StatusCycler.nextOnClick(from: model.status)) } },
                    onSetStatus: { s in Task { await model.setStatus(s) } }
                )
                Text(Self.statusName(model.status), bundle: .module)
                    .font(LillistTypography.body)
                    .foregroundStyle(LillistColor.textBody)
                Spacer(minLength: 0)
            }
        }
    }

    private var datesSection: some View {
        section("Dates") {
            VStack(alignment: .leading, spacing: LillistSpacing.s) {
                dateRow(
                    label: "Start",
                    date: $model.start,
                    hasTime: $model.startHasTime
                )
                dateRow(
                    label: "Deadline",
                    date: $model.deadline,
                    hasTime: $model.deadlineHasTime
                )
            }
        }
    }

    @ViewBuilder
    private func dateRow(label: LocalizedStringKey, date: Binding<Date?>, hasTime: Binding<Bool>) -> some View {
        let isSet = Binding(
            get: { date.wrappedValue != nil },
            set: { date.wrappedValue = $0 ? (date.wrappedValue ?? Date()) : nil }
        )
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isSet) {
                Text(label, bundle: .module)
                    .font(LillistTypography.subheadline)
                    .foregroundStyle(LillistColor.textBody)
            }
            .toggleStyle(.rainbow)

            if let unwrapped = date.wrappedValue {
                let bound = Binding(get: { unwrapped }, set: { date.wrappedValue = $0 })
                DatePicker(
                    selection: bound,
                    displayedComponents: hasTime.wrappedValue ? [.date, .hourAndMinute] : [.date]
                ) {
                    EmptyView()
                }
                .labelsHidden()
                Toggle(isOn: hasTime) {
                    Text("Include time", bundle: .module)
                        .font(LillistTypography.caption)
                        .foregroundStyle(LillistColor.textMuted)
                }
                .toggleStyle(.rainbow)
            }
        }
    }

    private var pinSection: some View {
        Toggle(isOn: $model.isPinned) {
            Label {
                Text("Pinned", bundle: .module)
                    .font(LillistTypography.body)
                    .foregroundStyle(LillistColor.textBody)
            } icon: {
                Image(systemName: "pin.fill")
            }
        }
        .toggleStyle(.rainbow)
    }

    private var recurrenceSection: some View {
        section("Repeats") {
            Button {
                showRecurrenceSheet = true
            } label: {
                HStack {
                    Text(RecurrenceSummaryFormatter.string(for: model.recurrence.summary))
                        .font(LillistTypography.body)
                        .foregroundStyle(LillistColor.textBody)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(LillistTypography.caption)
                        .foregroundStyle(LillistColor.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("EditorRecurrenceRow")
        }
    }

    private var notesSection: some View {
        section("Notes") {
            TextEditor(text: $model.notes)
                .font(LillistTypography.body)
                .foregroundStyle(LillistColor.textBody)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(LillistSpacing.s)
                .background {
                    RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                        .fill(.rainbowWell)
                }
                .accessibilityIdentifier("EditorNotesField")
        }
    }

    private var footer: some View {
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
            HStack(spacing: LillistSpacing.m) {
                if model.presentation == .existing {
                    Button(role: .destructive) {
                        Task { await model.deleteTask(); onDismiss() }
                    } label: {
                        Text("Delete", bundle: .module)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RainbowPalette.actionOrange.ink)
                }
                Spacer(minLength: 0)
                Button(action: dismissEditor) {
                    Text("Done", bundle: .module)
                }
                .buttonStyle(.rainbow(.lavender, size: .sm))
                .accessibilityIdentifier("EditorDoneButton")
            }
        }
    }

    // MARK: - Recurrence sheet

    private var recurrenceSheet: some View {
        NavigationStack {
            RecurrenceEditorView(viewModel: $model.recurrence)
                .navigationTitle(Text("Repeats", bundle: .module))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showRecurrenceSheet = false
                        } label: { Text("Cancel", bundle: .module) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            showRecurrenceSheet = false
                            Task { try? await model.commitRecurrence() }
                        } label: { Text("Save", bundle: .module) }
                    }
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

    private func expand() {
        if reduceMotion {
            model.expandToFull()
        } else {
            withAnimation(LillistMotion.squish(LillistMotion.slow)) {
                model.expandToFull()
            }
        }
    }

    private func dismissEditor() {
        Task {
            await model.saveTextNow()
            onDismiss()
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

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LillistSpacing.s) {
            Text(title, bundle: .module)
                .font(LillistTypography.caption)
                .foregroundStyle(LillistColor.textMuted)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func statusName(_ s: Status) -> LocalizedStringKey {
        switch s {
        case .todo: return "To-do"
        case .started: return "Started"
        case .blocked: return "Blocked"
        case .closed: return "Closed"
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
