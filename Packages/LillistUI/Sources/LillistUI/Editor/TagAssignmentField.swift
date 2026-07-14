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
public struct TagAssignmentField: View {
    public var tagNames: [String]
    public var onAdd: (String) -> Void
    public var onRemove: (String) -> Void

    @State private var isEditing = false
    @State private var draftName: String = ""
    @FocusState private var fieldFocused: Bool

    public init(
        tagNames: [String],
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void
    ) {
        self.tagNames = tagNames
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
        .focused($fieldFocused)
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
        .onAppear { fieldFocused = true }
        .onChange(of: fieldFocused) { _, focused in
            // Losing focus (tap-away) ends editing without adding a partial tag.
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
