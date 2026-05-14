import SwiftUI

public struct CrashReportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bodyText: String

    public init(body: String) {
        self.bodyText = body
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                Text(bodyText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("What will be sent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
