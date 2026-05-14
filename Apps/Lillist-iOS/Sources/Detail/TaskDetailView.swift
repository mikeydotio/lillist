import SwiftUI

/// Placeholder for the task detail surface. Replaced by Task 13.
struct TaskDetailView: View {
    let taskID: UUID

    var body: some View {
        Text("Task \(taskID.uuidString)")
            .navigationTitle("Task")
    }
}
