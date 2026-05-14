import SwiftUI
import LillistUI

struct NoSelectionDetailView: View {
    var body: some View {
        EmptyStateView(title: "No task selected",
                       message: "Pick a task from the list to see its details, notes, and journal.",
                       systemImage: "doc.text")
    }
}
