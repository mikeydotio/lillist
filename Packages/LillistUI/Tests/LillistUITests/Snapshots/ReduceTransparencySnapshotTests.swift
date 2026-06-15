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
    /// Quarantined (2026-06-15) for two reasons:
    /// 1. On OS 26 the seam deliberately does NOT branch on
    ///    `reduceTransparencyOverride` for the glass path — the Liquid
    ///    Glass renderer self-handles Reduce Transparency
    ///    (`GlassSurfaceModifier`). So these tests no longer exercise the
    ///    opaque fallback at all: both on/off render identical glass.
    /// 2. That glass cannot be captured offscreen on the macOS 26 host
    ///    (CGWindowListCreateImage obsoleted in 15; ScreenCaptureKit needs
    ///    Screen Recording permission). The pre-26 opaque-fallback *logic*
    ///    remains unit-covered in `GlassSurfaceTests`
    ///    (`prefersSolidFallback` / chrome-vs-fill).
    /// See docs/engineering-notes.md 2026-06-15.
    nonisolated override func setUpWithError() throws {
        throw XCTSkip("OS-26 glass self-handles Reduce Transparency and isn't offscreen-snapshottable — see docs/engineering-notes.md 2026-06-15; fallback logic is in GlassSurfaceTests")
    }

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
