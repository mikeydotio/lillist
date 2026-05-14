#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

@MainActor
final class QuickCaptureViewSnapshotTests: XCTestCase {
    func test_empty_light() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                StatefulPreview(text: "")
            },
            size: CGSize(width: 560, height: 120)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 560, height: 120)))
    }

    func test_with_tags_and_date_dark() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .dark) {
                StatefulPreview(text: "Ship release #work #urgent ^tomorrow")
            },
            size: CGSize(width: 560, height: 140)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 560, height: 140)))
    }

    private struct StatefulPreview: View {
        @State var text: String
        var body: some View {
            QuickCaptureView(text: $text, onSubmit: { _ in }, onCancel: {})
                .padding()
        }
    }
}
#endif
