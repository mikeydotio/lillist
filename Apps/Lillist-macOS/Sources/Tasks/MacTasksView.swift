import SwiftUI
import LillistCore
import LillistUI

/// Container for the macOS main window — the macOS analogue of the iOS
/// `TasksView`. Owns the fetch/reload lifecycle, the AppStorage-backed
/// sort selection, the ephemeral filter state, the `DragController`
/// lifecycle, and the in-window unified-editor wiring. Presentation is
/// delegated to the shared `LillistUI.TasksScreen` — the macOS main
/// window is now "the iOS app running on a Mac."
///
/// Divergences from the iOS container, all to fit the desktop shell:
/// - **Settings** opens the native Preferences scene via the
///   `openSettings` environment action (not an in-window sheet).
/// - The editor is hosted by `MacTaskEditorHost` (NSOpenPanel
///   attachments) instead of the iOS `TaskEditorHost` (PhotosPicker).
/// - Three desktop notifications are observed: the Dock menu's
///   "Show Today" / pinned-filter navigation, and the global-hotkey
///   `QuickCapturePanelController`'s `.lillistTasksDidChange` so a
///   hotkey-captured task appears without a manual refresh.
struct MacTasksView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.isQuickCapturePresentedBinding) private var isQuickCapturePresented
    @Environment(\.sortBinding) private var sortBinding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    @State private var records: [TaskStore.TaskRecord] = []
    @State private var savedFilters: [SmartFilterStore.SmartFilterRecord] = []
    @State private var loadError: String?

    @State private var collapsedNodeIDs: Set<UUID> = []
    @State private var isFilterHeaderExpanded: Bool = false
    @State private var searchText: String = ""
    @State private var selectedTokens: Set<QuickFilterToken> = []
    @State private var selectedSavedFilters: Set<UUID> = []

    @State private var searchDebounceTask: Task<Void, Never>?

    /// Suppresses the row-insertion animation on the very first populate
    /// (empty → N rows on launch). Every reload after the first animates
    /// the diff. Mirrors the iOS container.
    @State private var hasLoadedOnce = false

    @StateObject private var dragController = DragController()

    // Pull-to-refresh archive state (the macOS list supports the same
    // trackpad pull-to-refresh as iOS). `lastArchivedBatch` is the IDs
    // the most recent refresh flipped — undo only restores those.
    @State private var isArchiveToastPresented = false
    @State private var lastArchivedCount: Int = 0
    @State private var lastArchivedBatch: [UUID] = []

    @State private var isReorderToastPresented = false
    @State private var isStatusToastPresented = false

    /// Set by a row tap to open the unified editor for that task (observed
    /// by `MacTaskEditorHost`).
    @State private var openTaskID: UUID?

    var body: some View {
        TasksScreen(
            roots: tree,
            loadError: loadError,
            buildVersion: env.buildVersion,
            sort: sortBinding,
            isFilterHeaderExpanded: $isFilterHeaderExpanded,
            searchText: $searchText,
            selectedTokens: $selectedTokens,
            selectedSavedFilters: $selectedSavedFilters,
            isArchiveToastPresented: $isArchiveToastPresented,
            isReorderToastPresented: $isReorderToastPresented,
            isStatusToastPresented: $isStatusToastPresented,
            savedFilters: savedFilterSpecs,
            collapsedNodeIDs: collapsedNodeIDs,
            archivedCount: lastArchivedCount,
            dragController: dragController,
            onToggleCollapsed: { id in
                if collapsedNodeIDs.contains(id) {
                    collapsedNodeIDs.remove(id)
                } else {
                    collapsedNodeIDs.insert(id)
                }
            },
            onRefresh: { await performRefreshArchive() },
            onStatusClick: { record in Task { await cycle(record) } },
            onStatusSet: { record, newStatus in
                Task { await setStatus(record, to: newStatus) }
            },
            onDelete: { record in
                Task {
                    try? await env.taskStore.softDelete(id: record.id)
                    await reload()
                }
            },
            onClearFilter: {
                searchText = ""
                selectedTokens.removeAll()
                selectedSavedFilters.removeAll()
            },
            onOpenSettings: {
                openSettings()
            },
            onUndoArchive: { Task { await undoArchive() } },
            onOpenTask: { id in openTaskID = id }
        )
        .environment(\.quickCaptureAction, { isQuickCapturePresented.wrappedValue = true })
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton(onTap: { isQuickCapturePresented.wrappedValue = true })
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .accessibilityIdentifier("TasksQuickCaptureFAB")
        }
        .modifier(MacTaskEditorHost(
            newCaptureTrigger: isQuickCapturePresented,
            openTaskID: $openTaskID,
            stores: editorStores,
            onChanged: { await reload() }
        ))
        .task { await initialLoad() }
        .onAppear {
            dragController.setOnDrop { dragged, target in
                Task { await applyDrop(dragged: dragged, target: target) }
            }
            dragController.diagnosticLog = env.diagnosticLog
        }
        .onChange(of: sortBinding.wrappedValue) { _, _ in Task { await reload() } }
        .onChange(of: selectedTokens) { _, _ in Task { await reload() } }
        .onChange(of: selectedSavedFilters) { _, _ in Task { await reload() } }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                if searchText == newValue {
                    await reload()
                }
            }
        }
        // Dock menu "Show Today" → focus the Today quick-filter chip.
        .onReceive(NotificationCenter.default.publisher(for: .lillistSelectTodayFilter)) { _ in
            selectedTokens = [.today]
            isFilterHeaderExpanded = true
        }
        // Dock menu pinned-filter → select that saved filter.
        .onReceive(NotificationCenter.default.publisher(for: .lillistSelectFilter)) { note in
            if let id = note.userInfo?["id"] as? UUID {
                selectedSavedFilters = [id]
                isFilterHeaderExpanded = true
            }
        }
        // Global-hotkey panel committed a change → refresh the list.
        .onReceive(NotificationCenter.default.publisher(for: .lillistTasksDidChange)) { _ in
            Task { await reload() }
        }
    }

    // MARK: - Derived

    /// Store bundle for the unified editor, assembled from the environment.
    private var editorStores: TaskEditorModel.Stores {
        TaskEditorModel.Stores(
            tasks: env.taskStore,
            tags: env.tagStore,
            series: env.seriesStore,
            journal: env.journalStore,
            notifications: env.notificationSpecStore,
            attachments: env.attachmentStore
        )
    }

    private var tree: [TaskNode] {
        TaskTree.build(
            records: records,
            tagsByTask: [:],
            sort: sortBinding.wrappedValue
        )
    }

    private var savedFilterSpecs: [SavedFilterChipSpec] {
        savedFilters
            .filter { $0.isPinned }
            .sorted { $0.position < $1.position }
            .map { SavedFilterChipSpec(id: $0.id, title: $0.name) }
    }

    // MARK: - Load

    private func initialLoad() async {
        await loadSavedFilters()
        try? await env.taskStore.normalizeSiblingsIfDegenerate(ofParent: nil)
        await reload()
    }

    private func loadSavedFilters() async {
        do {
            try? await env.smartFilterStore.normalizeIfDegenerate()
            savedFilters = try await env.smartFilterStore.list()
        } catch {
            // Saved filters are an additive convenience; silently surface
            // as empty rather than blocking the whole view.
            savedFilters = []
        }
    }

    /// Reload the active list. The `records` reassignment runs inside an
    /// explicit `withAnimation` transaction so SwiftUI `List` drives its
    /// native row insert/remove/move animations off the stable
    /// `FlatTaskRow` identity. Reduce Motion drops to no animation; the
    /// first populate is unanimated (see `hasLoadedOnce`). Mirrors iOS.
    private func reload() async {
        do {
            let group = buildActivePredicateGroup()
            let newRecords = try await env.smartFilterStore.evaluate(
                group: group,
                sort: storeSortField,
                ascending: storeSortAscending,
                includeArchived: selectedTokens.contains(.done)
            )
            let animation: Animation? = (reduceMotion || !hasLoadedOnce)
                ? nil
                : LillistMotion.easeOut(LillistMotion.base)
            withAnimation(animation) {
                records = newRecords
                loadError = nil
            }
            hasLoadedOnce = true
        } catch {
            loadError = "\(error)"
            records = []
        }
    }

    // MARK: - Predicate composition

    /// Compose the active predicate from the user's quick tokens, saved
    /// filters, and search text. Mirrors the iOS container verbatim so the
    /// two platforms filter identically.
    private func buildActivePredicateGroup() -> PredicateGroup {
        var predicates: [LillistCore.Predicate] = []

        if selectedTokens.contains(.done) {
            predicates.append(
                .leaf(Leaf(field: .status, op: .is, value: .statusSet([.closed])))
            )
        }

        if selectedTokens.contains(.today) {
            predicates.append(.group(PredicateGroup(
                combinator: .any,
                predicates: [
                    .leaf(Leaf(field: .deadline, op: .on, value: .relativeDate(.today))),
                    .leaf(Leaf(field: .start, op: .on, value: .relativeDate(.today)))
                ]
            )))
        }

        if selectedTokens.contains(.thisWeek) {
            predicates.append(.group(PredicateGroup(
                combinator: .any,
                predicates: [
                    .leaf(Leaf(field: .deadline, op: .withinNextDays, value: .dayCount(7))),
                    .leaf(Leaf(field: .start, op: .withinLastDays, value: .dayCount(7)))
                ]
            )))
        }

        for id in selectedSavedFilters {
            if let filter = savedFilters.first(where: { $0.id == id }) {
                predicates.append(.group(filter.group))
            }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            predicates.append(
                .leaf(Leaf(field: .title, op: .contains, value: .string(trimmed)))
            )
        }

        return PredicateGroup(combinator: .all, predicates: predicates)
    }

    private var storeSortField: SortField {
        switch sortBinding.wrappedValue {
        case .personalized: return .manualPosition
        case .due: return .deadline
        case .modified: return .modifiedAt
        }
    }

    private var storeSortAscending: Bool {
        switch sortBinding.wrappedValue {
        case .personalized, .due: return true
        case .modified: return false
        }
    }

    // MARK: - Pull-to-refresh archive

    private func performRefreshArchive() async {
        guard !selectedTokens.contains(.done) else {
            await reload()
            return
        }
        let candidates = records.compactMap { $0.status == .closed ? $0.id : nil }
        guard !candidates.isEmpty else {
            await reload()
            return
        }
        let archived = (try? await env.taskStore.archive(ids: candidates)) ?? []
        await reload()
        guard !archived.isEmpty else { return }
        lastArchivedBatch = archived
        lastArchivedCount = archived.count
        isArchiveToastPresented = true
    }

    private func undoArchive() async {
        let ids = lastArchivedBatch
        guard !ids.isEmpty else { return }
        try? await env.taskStore.unarchive(ids: ids)
        lastArchivedBatch = []
        lastArchivedCount = 0
        isArchiveToastPresented = false
        await reload()
    }

    // MARK: - Drop routing

    /// Route a resolved drag-drop to the appropriate `TaskStore` mutation
    /// using the shared `DragDropResolver` (single source of truth shared
    /// with the iOS container).
    @MainActor
    private func applyDrop(dragged: UUID, target: DragTarget) async {
        do {
            switch DragDropResolver.resolve(target: target) {
            case .reorder(let parent, let after, let before):
                try await env.taskStore.reorder(
                    id: dragged, after: after, before: before, parent: .explicit(parent)
                )
            case .reparent(let newParent):
                try await env.taskStore.reparent(id: dragged, newParent: newParent)
            case .noop:
                break
            }
            await reload()
        } catch {
            isReorderToastPresented = true
            await reload()
        }
    }

    // MARK: - Mutations

    private func cycle(_ record: TaskStore.TaskRecord) async {
        let next = StatusCycler.nextOnClick(from: record.status)
        await setStatus(record, to: next)
    }

    /// A failed transition surfaces the transient status toast — never
    /// swallow it silently (dead-status-tap RCA, 2026-06-12).
    private func setStatus(_ record: TaskStore.TaskRecord, to newStatus: Status) async {
        do {
            try await env.taskStore.transition(id: record.id, to: newStatus)
        } catch {
            isStatusToastPresented = true
        }
        await reload()
    }
}
