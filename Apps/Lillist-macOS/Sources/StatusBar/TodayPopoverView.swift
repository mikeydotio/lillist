import SwiftUI
import CoreData
import LillistCore
import LillistUI

struct TodayPopoverView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tasks: [TaskStore.TaskRecord] = []
    /// LIL-97: this popover is *always* flat (no `TaskTree`/nesting concept
    /// at all — design doc §7's "flat list" case), so a subtask's parent
    /// isn't just possibly off-screen, it's never shown regardless. A task
    /// counts as needing a breadcrumb when its true parent isn't a member
    /// of this popover's own task set — membership, not `TaskTree`
    /// promotion, since there's no tree here to promote anything out of.
    @State private var breadcrumbsByTaskID: [UUID: [String]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(LillistTypography.title3)
                .foregroundStyle(LillistColor.textStrong)
                .padding(.bottom, 2)
            if tasks.isEmpty {
                Text("Nothing scheduled for today.")
                    .font(LillistTypography.subheadline)
                    .foregroundStyle(LillistColor.textMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(tasks, id: \.id) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        TaskRowView(task: t, tagNames: [],
                                    onStatusClick: { Task { await setStatus(t, to: StatusCycler.nextOnClick(from: t.status)) } },
                                    onStatusSet: { newStatus in Task { await setStatus(t, to: newStatus) } })
                        if let path = breadcrumbsByTaskID[t.id], !path.isEmpty {
                            BreadcrumbView(path: path)
                                .padding(.leading, LillistSpacing.xs + 2)
                        }
                    }
                    .rainbowCard(
                        accent: StatusPalette.color(for: t.status),
                        isDone: t.status == .closed
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 320, height: 360)
        .background(LillistColor.workspace)
        .onAppear { Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        do {
            let today = try await env.smartFilterStore.fetch(byName: "Today")
            tasks = try await env.smartFilterStore.evaluate(id: today.id)
        } catch {
            tasks = []
        }
        await loadBreadcrumbs()
    }

    private func loadBreadcrumbs() async {
        let memberIDs = Set(tasks.map(\.id))
        let orphanIDs = tasks.compactMap { task -> UUID? in
            guard let parentID = task.parentID, !memberIDs.contains(parentID) else { return nil }
            return task.id
        }
        guard !orphanIDs.isEmpty else {
            breadcrumbsByTaskID = [:]
            return
        }
        breadcrumbsByTaskID = (try? await env.taskStore.breadcrumbs(for: orphanIDs)) ?? [:]
    }

    private func setStatus(_ rec: TaskStore.TaskRecord, to newStatus: Status) async {
        _ = try? await env.taskStore.transition(id: rec.id, to: newStatus)
        await load()
    }
}
