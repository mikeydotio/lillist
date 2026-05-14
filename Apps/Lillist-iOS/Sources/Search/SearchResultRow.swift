import SwiftUI
import LillistCore
import LillistUI

struct SearchResultRow: View {
    let task: TaskStore.TaskRecord
    let tagNames: [String]

    var body: some View {
        TaskRowView(
            task: task,
            tagNames: tagNames,
            onStatusClick: {},
            onStatusLongPress: {}
        )
    }
}
