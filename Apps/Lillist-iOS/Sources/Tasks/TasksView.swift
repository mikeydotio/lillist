import SwiftUI
import LillistCore
import LillistUI
import LillistSearchIntelligence

/// Container for the single primary iOS surface. Owns the fetch and
/// reload lifecycle, the AppStorage-backed sort selection, the
/// ephemeral filter state, and the navigation destination wiring. The
/// presentation is delegated to `LillistUI.TasksScreen`.
struct TasksView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isQuickCapturePresentedBinding) private var isQuickCapturePresented
    @Environment(\.sortBinding) private var sortBinding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var records: [TaskStore.TaskRecord] = []
    @State private var savedFilters: [SmartFilterStore.SmartFilterRecord] = []
    @State private var loadError: String?

    @State private var collapsedNodeIDs: Set<UUID> = []
    @State private var isFilterHeaderExpanded: Bool = false
    @State private var searchText: String = ""
    @State private var selectedTokens: Set<QuickFilterToken> = []
    @State private var selectedSavedFilters: Set<UUID> = []
    @State private var isSettingsPresented = false

    @State private var searchDebounceTask: Task<Void, Never>?

    // Smart (natural-language) search — issue #51. `isSmartMode` is
    // explicit-toggle, submit-driven: translation costs hundreds of
    // ms–seconds, so it never rides the 250ms plain-search debounce above.
    @State private var isSmartMode = false
    @State private var smartState: SmartSearchState = .idle
    @State private var translatedQuery: TranslatedQuery?
    @State private var smartSearchTask: Task<Void, Never>?
    @State private var isSaveFilterPresented = false
    @State private var saveFilterName = ""

    /// Suppresses the row-insertion animation on the very first populate
    /// (empty → N rows on launch), where an animated cascade reads as a
    /// flourish rather than a meaningful change. Every reload after the
    /// first animates the diff.
    @State private var hasLoadedOnce = false

    @StateObject private var dragController = DragController()

    // Pull-to-refresh archive state. `lastArchivedBatch` is the IDs the
    // most recent refresh actually flipped — undo only restores those,
    // so a quick second pull doesn't accidentally resurrect an older
    // batch the user thought they'd dismissed.
    @State private var isArchiveToastPresented = false
    @State private var lastArchivedCount: Int = 0
    @State private var lastArchivedBatch: [UUID] = []

    @State private var isReorderToastPresented = false
    @State private var isStatusToastPresented = false

    /// Set by a row tap to open the unified editor for that task (observed by
    /// `TaskEditorHost`).
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
            isSmartModeAvailable: isSmartModeAvailable,
            isSmartMode: $isSmartMode,
            smartState: smartState,
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
                isSettingsPresented = true
            },
            onUndoArchive: { Task { await undoArchive() } },
            onOpenTask: { id in openTaskID = id },
            onSubmitSearch: { submitSearch() },
            onSaveSmartFilter: {
                saveFilterName = ""
                isSaveFilterPresented = true
            }
        )
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
        }
        .alert(
            String(localized: "Save as Smart Filter"),
            isPresented: $isSaveFilterPresented
        ) {
            TextField(String(localized: "Name"), text: $saveFilterName)
            Button(String(localized: "Save")) {
                Task { await saveSmartFilter() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .environment(\.quickCaptureAction, { isQuickCapturePresented.wrappedValue = true })
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton(onTap: { isQuickCapturePresented.wrappedValue = true })
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .accessibilityIdentifier("TasksQuickCaptureFAB")
        }
        .modifier(TaskEditorHost(
            newCaptureTrigger: isQuickCapturePresented,
            openTaskID: $openTaskID,
            captureSeed: Binding(
                get: { env.pendingQuickCaptureSeed },
                set: { env.pendingQuickCaptureSeed = $0 }
            ),
            stores: editorStores,
            onChanged: { await reload() }
        ))
        .task { await initialLoad(); drainPendingDeepLinks() }
        .onChange(of: env.pendingSelectedFilterID) { _, _ in drainPendingDeepLinks() }
        .onChange(of: env.pendingOpenTaskID) { _, _ in drainPendingDeepLinks() }
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
            // In smart mode, `searchText` changes as the user types their
            // natural-language query — never live-filter on it (translation
            // is submit-driven, see `submitSearch()`).
            guard !isSmartMode else { return }
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                if searchText == newValue {
                    await reload()
                }
            }
        }
        .onChange(of: isSmartMode) { _, newValue in
            if !newValue {
                smartSearchTask?.cancel()
                translatedQuery = nil
                smartState = .idle
                Task { await reload() }
            }
        }
    }

    // MARK: - Derived

    /// Whether to offer the smart-search toggle at all — a static,
    /// device-level capability check (Apple Intelligence on-device or
    /// Private Cloud Compute availability), consulted once per body
    /// evaluation rather than cached, so it reflects a live availability
    /// change (e.g. Apple Intelligence toggled in Settings) without
    /// requiring a relaunch.
    private var isSmartModeAvailable: Bool {
        FilterTranslatorFactory.isAgenticSearchSupported
    }

    /// Store bundle for the unified editor, assembled from the environment.
    private var editorStores: TaskEditorModel.Stores {
        TaskEditorModel.Stores(
            tasks: env.taskStore,
            tags: env.tagStore,
            series: env.seriesStore,
            journal: env.journalStore,
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

    /// Consume `lillist://` deep links handed off by the widget: a filter link
    /// focuses that filter (and expands the header); a task link opens that task
    /// in the editor. Idempotent — clears each pending id so it fires once.
    private func drainPendingDeepLinks() {
        if let id = env.pendingSelectedFilterID {
            selectedSavedFilters = [id]
            isFilterHeaderExpanded = true
            env.pendingSelectedFilterID = nil
        }
        if let id = env.pendingOpenTaskID {
            openTaskID = id
            env.pendingOpenTaskID = nil
        }
    }

    private func loadSavedFilters() async {
        do {
            try? await env.smartFilterStore.normalizeIfDegenerate()
            savedFilters = try await env.smartFilterStore.list()
        } catch {
            // Saved filters are an additive convenience; silently
            // surface as empty rather than blocking the whole view.
            savedFilters = []
        }
    }

    /// Reload the active list. The `records` reassignment runs inside an
    /// explicit `withAnimation` transaction so SwiftUI `List` drives its
    /// native row insert/remove/move animations off the stable
    /// `FlatTaskRow` identity — newly captured tasks slide into place,
    /// deletions and filter/sort changes settle with the same ~0.2s
    /// ease-out. Reduce Motion drops to no animation; the first populate
    /// is unanimated (see `hasLoadedOnce`).
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
    /// filters, and search text. Completed tasks are *not* filtered out
    /// by default — they stay visible in the list until the user
    /// pull-to-refreshes to archive them. The `.done` token still asks
    /// the store for closed-only and instructs `evaluate` to include
    /// archived rows so it acts as a full "history" view.
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

        if isSmartMode, let translatedQuery, !translatedQuery.isEmpty {
            predicates.append(.group(translatedQuery.group))
        } else if !isSmartMode {
            let trimmed = searchText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                predicates.append(
                    .leaf(Leaf(field: .title, op: .contains, value: .string(trimmed)))
                )
            }
        }

        return PredicateGroup(combinator: .all, predicates: predicates)
    }

    // MARK: - Smart search

    /// Runs on the search field's Return key while in smart mode (never on
    /// every keystroke — translation costs hundreds of ms–seconds). An
    /// empty query resets to the plain, unfiltered list.
    private func submitSearch() {
        guard isSmartMode else { return }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            translatedQuery = nil
            smartState = .idle
            Task { await reload() }
            return
        }
        smartSearchTask?.cancel()
        smartSearchTask = Task {
            smartState = .translating
            guard let translator = FilterTranslatorFactory.makeBest() else {
                smartState = .unsupported
                return
            }
            do {
                let tags = try await env.tagStore.list()
                let context = TranslationContext(knownTags: tags.map { TagRef(id: $0.id, name: $0.name) })
                let result = try await translator.translate(query, context: context)
                if Task.isCancelled { return }
                translatedQuery = result
                smartState = .translated(explanation: result.explanation, unmappedTerms: result.unmappedTerms)
                await reload()
            } catch {
                if Task.isCancelled { return }
                let message = (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "Smart search failed.")
                smartState = .failed(message: message)
            }
        }
    }

    /// Persists the current translated query as a durable, editable saved
    /// filter — the payoff for a good natural-language query.
    private func saveSmartFilter() async {
        guard let translatedQuery, !translatedQuery.isEmpty else { return }
        let name = saveFilterName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            _ = try await env.smartFilterStore.create(name: name, group: translatedQuery.group)
            await loadSavedFilters()
        } catch {
            // Saved filters are an additive convenience; a failed save
            // leaves the live smart-search result unaffected.
        }
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

    /// Pull-to-refresh handler. In the default view, archives every
    /// currently-visible closed task and triggers the undo banner. In the
    /// Done view (where the user is intentionally browsing completed
    /// tasks) it falls back to a plain reload so the gesture doesn't hide
    /// the very thing the user is trying to look at.
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
    /// with macOS `TaskListView.applyDrop`).
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
    /// swallow it silently (dead-status-tap RCA, 2026-06-12): a tap
    /// whose write fails must be distinguishable from a tap that never
    /// fired.
    private func setStatus(_ record: TaskStore.TaskRecord, to newStatus: Status) async {
        do {
            try await env.taskStore.transition(id: record.id, to: newStatus)
        } catch {
            isStatusToastPresented = true
        }
        await reload()
    }

}
