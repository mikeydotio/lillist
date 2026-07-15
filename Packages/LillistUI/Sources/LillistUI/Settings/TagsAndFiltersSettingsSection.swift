import SwiftUI

/// Cross-platform Settings surface for managing saved tags and smart filters.
///
/// Pure presentation (container/presenter split, like ``ICloudSyncSettingsSection``):
/// the iOS `TagsAndFiltersSection` and macOS `TagsAndFiltersPane` wrappers own the
/// `AppEnvironment` state, host the edit sheet on their stable `Form` container, and
/// map store records into ``ViewState``. Rows emit intent through ``Actions``; no
/// store call and no `.sheet` live here — a sheet attached to `Section`/Form-row
/// content tears down the whole Settings sheet (see `ICloudSyncSection`).
///
/// Tags render as a depth-indented tree so nested tags stay manageable; filters
/// carry an inline pin toggle because pinning is the only way a saved filter
/// surfaces in the task view.
public struct TagsAndFiltersSettingsSection: View {
    public struct ViewState: Equatable, Sendable {
        public var tags: [TagNode]
        public var filters: [SavedFilterRow]

        public init(tags: [TagNode], filters: [SavedFilterRow]) {
            self.tags = tags
            self.filters = filters
        }
    }

    public struct Actions {
        public var editTag: (TagNode) -> Void
        public var editFilter: (SavedFilterRow) -> Void
        public var setFilterPinned: (UUID, Bool) -> Void

        public init(
            editTag: @escaping (TagNode) -> Void,
            editFilter: @escaping (SavedFilterRow) -> Void,
            setFilterPinned: @escaping (UUID, Bool) -> Void
        ) {
            self.editTag = editTag
            self.editFilter = editFilter
            self.setFilterPinned = setFilterPinned
        }
    }

    public let viewState: ViewState
    public let actions: Actions

    public init(viewState: ViewState, actions: Actions) {
        self.viewState = viewState
        self.actions = actions
    }

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Group {
            tagsSection
            filtersSection
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section {
            if viewState.tags.isEmpty {
                Text("No tags yet. Tags you add to tasks show up here.", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(LillistColor.textMuted)
            } else {
                ForEach(viewState.tags) { tag in
                    Button {
                        actions.editTag(tag)
                    } label: {
                        HStack(spacing: LillistSpacing.s) {
                            swatch(for: tag.tintHex)
                            Text(tag.name)
                                .foregroundStyle(LillistColor.textStrong)
                            Spacer(minLength: 0)
                            disclosureChevron
                        }
                        .padding(.leading, CGFloat(tag.depth) * LillistSpacing.l)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Edit tag", bundle: .module))
                }
            }
        } header: {
            Text("Tags", bundle: .module)
        }
    }

    // MARK: - Saved filters

    private var filtersSection: some View {
        Section {
            if viewState.filters.isEmpty {
                Text("No saved filters yet.", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(LillistColor.textMuted)
            } else {
                ForEach(viewState.filters) { filter in
                    HStack(spacing: LillistSpacing.m) {
                        pinButton(for: filter)
                        Button {
                            actions.editFilter(filter)
                        } label: {
                            HStack(spacing: LillistSpacing.s) {
                                swatch(for: filter.tintHex)
                                Text(filter.name)
                                    .foregroundStyle(LillistColor.textStrong)
                                Spacer(minLength: 0)
                                disclosureChevron
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Edit filter", bundle: .module))
                    }
                }
            }
        } header: {
            Text("Saved Filters", bundle: .module)
        } footer: {
            Text("Pinned filters appear as quick chips above your task list.", bundle: .module)
                .font(.footnote)
                .foregroundStyle(LillistColor.textMuted)
        }
    }

    private func pinButton(for filter: SavedFilterRow) -> some View {
        Button {
            actions.setFilterPinned(filter.id, !filter.isPinned)
        } label: {
            Image(systemName: filter.isPinned ? "pin.fill" : "pin")
                .foregroundStyle(filter.isPinned ? RainbowPalette.scriptPurple.base : LillistColor.textFaint)
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.isPinned
            ? Text("Unpin filter", bundle: .module)
            : Text("Pin filter", bundle: .module))
        .accessibilityAddTraits(filter.isPinned ? [.isSelected] : [])
    }

    // MARK: - Shared row chrome

    private var disclosureChevron: some View {
        Image(systemName: "chevron.forward")
            .font(.caption.weight(.semibold))
            .foregroundStyle(LillistColor.textFaint)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func swatch(for hex: String?) -> some View {
        Circle()
            .fill(TagTint(hex: hex)?.resolved(in: colorScheme).color ?? LillistColor.textFaint.opacity(0.35))
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
