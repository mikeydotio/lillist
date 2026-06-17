import SwiftUI

/// Net-new tag assignment surface for the unified editor. Displays the
/// currently-assigned (or buffered-draft) tags as removable chips and offers
/// an add field that creates/assigns on submit.
///
/// Presentation-only: the host wires `onAdd` / `onRemove` to the model
/// (`addTag` / `removeTag`), which branches on draft-vs-live. No store access
/// here, so it stays `AppEnvironment`-free and snapshot-friendly.
public struct TagAssignmentField: View {
    public var tagNames: [String]
    public var onAdd: (String) -> Void
    public var onRemove: (String) -> Void

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
        VStack(alignment: .leading, spacing: LillistSpacing.s) {
            if !tagNames.isEmpty {
                WrapTags(names: tagNames, onRemove: onRemove)
            }
            HStack(spacing: LillistSpacing.s) {
                TextField(
                    text: $draftName,
                    prompt: Text("Add a tag", bundle: .module)
                ) {
                    Text("Add a tag", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(LillistTypography.body)
                .foregroundStyle(LillistColor.textStrong)
                .focused($fieldFocused)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier("TagAssignmentField")

                Button(action: commit) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(RainbowPalette.scriptPurple.base)
                }
                .buttonStyle(.plain)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(String(localized: "Add tag", bundle: .module))
            }
            .padding(.horizontal, LillistSpacing.m)
            .padding(.vertical, LillistSpacing.s)
            .background {
                RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                    .fill(.rainbowWell)
            }
        }
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        draftName = ""
        fieldFocused = true
    }
}

/// A simple wrapping row of removable tag chips. Uses a `Layout`-free flow via
/// `FlowLayout`-style wrapping is overkill here; a horizontally-scrolling row
/// keeps it deterministic for snapshots.
private struct WrapTags: View {
    var names: [String]
    var onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LillistSpacing.xs + 2) {
                ForEach(names, id: \.self) { name in
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
            }
            .padding(.vertical, 2)
        }
    }
}
