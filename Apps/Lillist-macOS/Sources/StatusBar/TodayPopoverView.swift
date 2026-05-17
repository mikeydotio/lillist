import SwiftUI
import CoreData
import LillistCore
import LillistUI

struct TodayPopoverView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tasks: [TaskStore.TaskRecord] = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Today").font(.headline).padding(.bottom, 4)
            if tasks.isEmpty {
                Text("Nothing scheduled for today.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(tasks, id: \.id) { t in
                    TaskRowView(task: t, tagNames: [],
                                onStatusClick: { Task { await setStatus(t, to: StatusCycler.nextOnClick(from: t.status)) } },
                                onStatusSet: { newStatus in Task { await setStatus(t, to: newStatus) } })
                }
            }
        }
        .padding()
        .frame(width: 320, height: 360)
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
    }

    private func setStatus(_ rec: TaskStore.TaskRecord, to newStatus: Status) async {
        try? await env.taskStore.transition(id: rec.id, to: newStatus)
        await load()
    }
}
