#if os(iOS)
import SwiftUI
import LillistCore

/// "All" tab — every open, non-trashed task. Pure presentation; the
/// hosting iOS app's `AllView` owns the fetch + reload state and the
/// `.navigationDestination` that turns a tapped row's UUID into a
/// `TaskDetailView`.
///
/// Mirrors `TodayScreen`'s shape. The two screens are kept as parallel
/// files (rather than sharing a parameterised base) so each can evolve
/// its own copy, sort, and toolbar surface without dragging the other
/// along. Plan: RCA — iOS new-task flow / 3-tab restructure.
public struct AllScreen: View {
    public var results: [TaskStore.TaskRecord]
    public var loadError: String?
    public var syncIndicator: SyncIndicator
    public var buildVersion: String?
    public var onRefresh: @MainActor () async -> Void
    public var onStatusClick: @MainActor (TaskStore.TaskRecord) -> Void
    public var onStatusSet: @MainActor (TaskStore.TaskRecord, Status) -> Void
    public var onComplete: @MainActor (TaskStore.TaskRecord) -> Void
    public var onSnooze: @MainActor (TaskStore.TaskRecord) -> Void
    public var onDelete: @MainActor (TaskStore.TaskRecord) -> Void

    @Environment(\.taskSelectionBinding) private var taskSelection
    @Environment(\.quickCaptureAction) private var quickCaptureAction

    public init(
        results: [TaskStore.TaskRecord],
        loadError: String? = nil,
        syncIndicator: SyncIndicator = .idle(lastSync: nil),
        buildVersion: String? = nil,
        onRefresh: @escaping @MainActor () async -> Void = {},
        onStatusClick: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onStatusSet: @escaping @MainActor (TaskStore.TaskRecord, Status) -> Void = { _, _ in },
        onComplete: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onSnooze: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onDelete: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in }
    ) {
        self.results = results
        self.loadError = loadError
        self.syncIndicator = syncIndicator
        self.buildVersion = buildVersion
        self.onRefresh = onRefresh
        self.onStatusClick = onStatusClick
        self.onStatusSet = onStatusSet
        self.onComplete = onComplete
        self.onSnooze = onSnooze
        self.onDelete = onDelete
    }

    public var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load tasks",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No tasks yet", bundle: .module),
                          systemImage: "checklist")
                } description: {
                    Text("Every open task shows up here. Capture one to get started.")
                } actions: {
                    Button {
                        quickCaptureAction()
                    } label: {
                        Label(String(localized: "Capture a task", bundle: .module),
                              systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("AllEmptyStateCaptureButton")
                }
            } else {
                listBody
            }
        }
        .navigationTitle(Text(String(localized: "All", bundle: .module)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusBadge(indicator: syncIndicator)
            }
        }
        .refreshable { await onRefresh() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let buildVersion {
                BuildVersionLabel(version: buildVersion)
            }
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if let taskSelection {
            List(selection: taskSelection) {
                ForEach(results, id: \.id) { record in
                    row(record).tag(record.id)
                }
            }
            .listStyle(.plain)
        } else {
            List {
                ForEach(results, id: \.id) { record in
                    NavigationLink(value: record.id) { row(record) }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(_ record: TaskStore.TaskRecord) -> some View {
        TaskRowView(
            task: record,
            tagNames: [],
            onStatusClick: { onStatusClick(record) },
            onStatusSet: { newStatus in onStatusSet(record, newStatus) }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(String(localized: "Complete", bundle: .module)) { onComplete(record) }
                .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(String(localized: "Snooze", bundle: .module)) { onSnooze(record) }
            Button(role: .destructive) {
                onDelete(record)
            } label: { Text(String(localized: "Delete", bundle: .module)) }
        }
        .contextMenu {
            Menu(String(localized: "Change status", bundle: .module)) {
                ForEach(Status.allCases, id: \.self) { s in
                    Button(StatusGlyph.accessibilityLabel(for: s)) {
                        onStatusSet(record, s)
                    }
                }
            }
            Button(role: .destructive) {
                onDelete(record)
            } label: { Text(String(localized: "Delete", bundle: .module)) }
        }
    }
}
#endif
