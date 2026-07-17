import SwiftUI

/// The tag row on the task detail card: the assigned (or buffered-draft) tags
/// as removable chips, followed by a **`+ Tag`** pill. Tapping the pill turns
/// it into a focused inline field; Return commits the tag and ends editing;
/// an empty Return or losing focus collapses back to the pill without adding.
///
/// Presentation-only: the host wires `onAdd` / `onRemove` to the model
/// (`addTag` / `removeTag`), which branches on draft-vs-live. No store access
/// here, so it stays `AppEnvironment`-free and snapshot-friendly. The default
/// (non-editing) state is fully deterministic for snapshots.
///
/// The editing state (`isEditing` / `draftName` / focus) is **externally
/// owned** by the host, not stored here: this view is embedded in the editor's
/// `ViewThatFits` wrap valve, whose two candidates are structurally-distinct
/// subtrees. If the state lived here it would reset every time the valve flips
/// (e.g. the keyboard rising on `+ Tag` shrinks the offered height and swaps
/// candidates), collapsing the open field mid-edit. Hoisting it to the host —
/// which sits above the valve — lets the field survive the swap.
public struct TagAssignmentField: View {
    public var tagNames: [String]
    @Binding public var isEditing: Bool
    @Binding public var draftName: String
    private var fieldFocused: FocusState<Bool>.Binding
    public var onAdd: (String) -> Void
    public var onRemove: (String) -> Void

    public init(
        tagNames: [String],
        isEditing: Binding<Bool>,
        draftName: Binding<String>,
        fieldFocused: FocusState<Bool>.Binding,
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void
    ) {
        self.tagNames = tagNames
        self._isEditing = isEditing
        self._draftName = draftName
        self.fieldFocused = fieldFocused
        self.onAdd = onAdd
        self.onRemove = onRemove
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LillistSpacing.xs + 2) {
                ForEach(tagNames, id: \.self) { name in
                    chip(name)
                }
                if isEditing {
                    editField
                } else {
                    addPill
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Pieces

    private func chip(_ name: String) -> some View {
        HStack(spacing: 4) {
            TagChipView(name: name)
            Button {
                onRemove(name)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(LillistTypography.caption)
                    .foregroundStyle(LillistColor.textFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove tag \(name)", bundle: .module))
        }
    }

    /// The collapsed affordance — matches `TagChipView.pill` metrics so it
    /// aligns with the real chips, but dashed + purple to read as "add".
    private var addPill: some View {
        Button(action: beginEditing) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(LillistTypography.caption)
                Text("Tag", bundle: .module)
                    .font(LillistTypography.subheadline)
            }
            .foregroundStyle(RainbowPalette.scriptPurple.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                Capsule().strokeBorder(
                    RainbowPalette.scriptPurple.base.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Add tag", bundle: .module))
        .accessibilityIdentifier("AddTagButton")
    }

    /// The expanded inline editor — a capsule-framed field, focus-highlighted.
    private var editField: some View {
        TextField(
            text: $draftName,
            prompt: Text("Tag name", bundle: .module)
        ) {
            Text("Tag name", bundle: .module)
        }
        .textFieldStyle(.plain)
        .font(LillistTypography.subheadline)
        .foregroundStyle(LillistColor.textStrong)
        .focused(fieldFocused)
        .submitLabel(.done)
        .onSubmit(commit)
        .frame(minWidth: 72)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(LillistColor.card))
        .overlay(
            Capsule().strokeBorder(
                RainbowPalette.focusBlue.base.opacity(0.45),
                lineWidth: 2
            )
        )
        .accessibilityIdentifier("TagAssignmentField")
        .onAppear { fieldFocused.wrappedValue = true }
        .onChange(of: fieldFocused.wrappedValue) { _, focused in
            // Losing focus collapses the field and discards the in-progress draft
            // *by design* — the contract at the top of this file (unchanged since
            // 08372592): only `commit()` adds a tag, so a tap-away never persists a
            // partial name.
            //
            // Hoisting the storage above the wrap valve keeps the inert
            // `isEditing`/`draftName` alive across a candidate swap (only this view
            // writes them). Focus is a different animal: SwiftUI writes to
            // `@FocusState` on first-responder lifecycle events, and it is
            // *re-asserted* on a surviving candidate by `.focused()` + `.onAppear`
            // (L128) — but the ordering of a removal-driven focus reset vs that
            // incoming `.onAppear` is NOT contractual. If the reset lands last, this
            // observer fires on a swap teardown, not only on a genuine tap-away. We
            // accept that: a swap already collapses the field, and discarding the
            // draft there matches the tap-away contract. Don't read this as a
            // guarantee the draft survives a swap — it does not.
            if !focused { endEditing() }
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draftName = ""
        isEditing = true
    }

    private func endEditing() {
        isEditing = false
        draftName = ""
    }

    /// Return: create/assign the trimmed tag (if any), then end editing —
    /// "editing mode ends on return" (issue #8, item 4).
    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onAdd(trimmed) }
        endEditing()
    }
}
