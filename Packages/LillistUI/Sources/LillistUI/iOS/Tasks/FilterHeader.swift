// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI
import LillistCore

/// One of the three built-in filter tokens. `Done` is special-cased by
/// `TasksView`: it replaces the default `status != closed` baseline
/// rather than AND-ing with it (otherwise the result is always empty).
public enum QuickFilterToken: String, CaseIterable, Identifiable, Sendable {
    case today
    case thisWeek
    case done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return String(localized: "Today", bundle: .module)
        case .thisWeek: return String(localized: "This Week", bundle: .module)
        case .done: return String(localized: "Done", bundle: .module)
        }
    }
}

/// Pinned-saved-filter chip. Lives separately from `QuickFilterToken`
/// so the header can render both groups with the same `FilterChip`
/// without confusing the binding state.
public struct SavedFilterChipSpec: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    /// Pinned filters, in canonical `SiblingOrder` (position ascending,
    /// then `id.uuidString` ascending on ties) — never a raw
    /// `position <`-only comparator (`L1`). Both `TasksView` (iOS) and
    /// `MacTasksView` (macOS) previously duplicated an identical
    /// `.sorted { $0.position < $1.position }` with no tie-break, which
    /// could diverge from `SmartFilterStore.list()`'s own canonical order
    /// (used everywhere else a filter list renders, including the
    /// Settings/Preferences surface) whenever two pinned filters shared a
    /// position — "the same rows render in opposite order on different
    /// surfaces." Consolidated here so both apps share one tie-break
    /// instead of re-deriving it, and so it's directly unit-testable
    /// (`nonisolated static`, not app-target `View` state).
    public nonisolated static func pinnedSorted(
        from filters: [SmartFilterStore.SmartFilterRecord]
    ) -> [SavedFilterChipSpec] {
        filters
            .filter(\.isPinned)
            .sorted {
                SiblingOrder.precedes(
                    positionA: $0.position, idA: $0.id,
                    positionB: $1.position, idB: $1.id
                )
            }
            .map { SavedFilterChipSpec(id: $0.id, title: $0.name) }
    }
}

/// Expanding filter header rendered above the Tasks list via
/// `safeAreaInset(edge: .top)`. Pure presentation — all state is owned
/// by the host (`TasksView`).
public struct FilterHeader: View {
    @Binding public var searchText: String
    @Binding public var selectedTokens: Set<QuickFilterToken>
    @Binding public var selectedSavedFilters: Set<UUID>
    public let savedFilters: [SavedFilterChipSpec]
    public let onClear: () -> Void

    /// Whether the smart-search toggle is offered at all — the host
    /// checks the translator factory's availability once and passes the
    /// result down; `FilterHeader` itself never touches FoundationModels.
    public var isSmartModeAvailable: Bool
    @Binding public var isSmartMode: Bool
    public var smartState: SmartSearchState
    /// Fires on the search field's Return key. A no-op in plain-search
    /// mode (live filtering already tracks `searchText`); in smart mode
    /// the host runs the natural-language translation — deliberately not
    /// on every keystroke, since translation costs hundreds of ms–seconds.
    public var onSubmitSearch: () -> Void
    public var onSaveSmartFilter: () -> Void

    public init(
        searchText: Binding<String>,
        selectedTokens: Binding<Set<QuickFilterToken>>,
        selectedSavedFilters: Binding<Set<UUID>>,
        savedFilters: [SavedFilterChipSpec],
        onClear: @escaping () -> Void,
        isSmartModeAvailable: Bool = false,
        isSmartMode: Binding<Bool> = .constant(false),
        smartState: SmartSearchState = .idle,
        onSubmitSearch: @escaping () -> Void = {},
        onSaveSmartFilter: @escaping () -> Void = {}
    ) {
        self._searchText = searchText
        self._selectedTokens = selectedTokens
        self._selectedSavedFilters = selectedSavedFilters
        self.savedFilters = savedFilters
        self.onClear = onClear
        self.isSmartModeAvailable = isSmartModeAvailable
        self._isSmartMode = isSmartMode
        self.smartState = smartState
        self.onSubmitSearch = onSubmitSearch
        self.onSaveSmartFilter = onSaveSmartFilter
    }

    @FocusState private var searchFocused: Bool

    public var body: some View {
        VStack(spacing: 10) {
            searchField
            if isSmartModeAvailable {
                SmartSearchField(
                    isAvailable: isSmartModeAvailable,
                    isSmartMode: $isSmartMode,
                    state: smartState,
                    onSave: onSaveSmartFilter
                )
            }
            chipScroll
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The header background floats above the scrolling list — a
        // control-layer panel. The inner search well stays a *sunken*
        // input (see `searchField`); glass is for raised surfaces only.
        .glassSurface(.panel, in: Rectangle())
        .overlay(alignment: .bottom) {
            LillistColor.borderHair.frame(height: 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LillistColor.textFaint)
            TextField(
                String(localized: "Search", bundle: .module),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(LillistTypography.body)
            .focused($searchFocused)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityIdentifier("FilterSearchField")
            .onSubmit(onSubmitSearch)

            if !searchText.isEmpty || !selectedTokens.isEmpty || !selectedSavedFilters.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LillistColor.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear filter", bundle: .module))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background {
            // The Rainbow inset search well: sunken surface when at
            // rest; lifts to card with a focus-blue ring while typing.
            Capsule(style: .continuous)
                .fill(searchFocused ? AnyShapeStyle(LillistColor.card) : .rainbowWell)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    searchFocused
                        ? RainbowPalette.focusBlue.base.opacity(0.35)
                        : LillistColor.borderHair,
                    lineWidth: searchFocused ? 2 : 1
                )
        }
    }

    private var chipScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickFilterToken.allCases) { token in
                    FilterChip(
                        title: token.title,
                        isSelected: selectedTokens.contains(token)
                    ) {
                        toggleToken(token)
                    }
                }
                if !savedFilters.isEmpty {
                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 4)
                }
                ForEach(savedFilters) { spec in
                    FilterChip(
                        title: spec.title,
                        isSelected: selectedSavedFilters.contains(spec.id)
                    ) {
                        toggleSavedFilter(spec.id)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func toggleToken(_ token: QuickFilterToken) {
        if selectedTokens.contains(token) {
            selectedTokens.remove(token)
        } else {
            selectedTokens.insert(token)
        }
    }

    private func toggleSavedFilter(_ id: UUID) {
        if selectedSavedFilters.contains(id) {
            selectedSavedFilters.remove(id)
        } else {
            selectedSavedFilters.insert(id)
        }
    }
}
