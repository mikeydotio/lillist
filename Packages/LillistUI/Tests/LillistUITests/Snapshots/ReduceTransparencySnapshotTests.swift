#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

/// Snapshot the QuickCaptureView under reduceTransparency=true.
/// Under the default environment the background renders as
/// `.regularMaterial`; under reduceTransparency=true it must render
/// as the opaque fallback color. We use the internal
/// `reduceTransparencyOverride` env key (SDK 26.2 exposes the
/// system `accessibilityReduceTransparency` value as read-only, so
/// the override is the only way to drive the code path under test).
@MainActor
final class ReduceTransparencySnapshotTests: RecordableSnapshotTestCase {
    func test_quickCapture_reduceTransparency_on() {
        let view = StatefulQuickCapture(text: "Buy milk")
            .environment(\.reduceTransparencyOverride, true)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 560, height: 140)),
                       as: .image(precision: 0.99),
                       named: "quickcapture-reduce-transparency")
    }

    func test_quickCapture_reduceTransparency_off() {
        let view = StatefulQuickCapture(text: "Buy milk")
            .environment(\.reduceTransparencyOverride, false)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 560, height: 140)),
                       as: .image(precision: 0.99),
                       named: "quickcapture-normal-transparency")
    }

    private struct StatefulQuickCapture: View {
        @State var text: String
        var body: some View {
            QuickCaptureView(text: $text, onSubmit: { _ in }, onCancel: {})
        }
    }
}
#endif
