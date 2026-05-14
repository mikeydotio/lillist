import SwiftUI
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
                                onStatusClick: {},
                                onStatusLongPress: {})
                }
            }
        }
        .padding()
        .frame(width: 320, height: 360)
        .task { await load() }
    }

    private func load() async {
        do {
            let today = try await env.smartFilterStore.fetch(byName: "Today")
            tasks = try await env.smartFilterStore.evaluate(id: today.id)
        } catch {
            tasks = []
        }
    }
}
