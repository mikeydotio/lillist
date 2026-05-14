import SwiftUI

/// Placeholder for the Quick Capture sheet. Replaced by Task 14.
struct QuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Quick Capture")
                .font(.headline)
            Button("Close") { dismiss() }
                .padding(.top)
        }
        .padding()
    }
}
