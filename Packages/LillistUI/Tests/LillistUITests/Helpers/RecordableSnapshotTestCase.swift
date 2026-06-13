import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Base class for every snapshot suite: re-records all baselines when
/// `RECORD_SNAPSHOTS=YES` is present in the test-process environment.
///
/// Two delivery routes, one switch:
/// - **Host (`swift test`)**: plain env passes through —
///   `RECORD_SNAPSHOTS=YES swift test --package-path Packages/LillistUI`.
/// - **Simulator (`xcodebuild test`)**: plain env does *not* reach the
///   test host (engineering-notes), so the `Lillist-iOS` scheme maps
///   the env var to `$(RECORD_SNAPSHOTS)` — a build setting you set on
///   the CLI: `xcodebuild test … RECORD_SNAPSHOTS=YES`.
///
/// This replaces the old ritual of temporarily threading
/// `record: .all` through per-suite helpers and reverting.
class RecordableSnapshotTestCase: XCTestCase {
    /// Whether this run re-records every baseline it touches.
    static var isRecordRun: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES"
    }

    /// One-time text-system warm-up. The very first hosted render with
    /// the custom Plus Jakarta Sans faces lays text out with unsettled
    /// metrics (observed as a vertically-clipped placeholder in the
    /// first `QuickCaptureView` snapshot of a fresh process); every
    /// subsequent render is stable. Rendering a throwaway line per
    /// typography token here makes the first *real* snapshot identical
    /// to the settled layout, so record runs and verify runs agree.
    @MainActor
    private static let textSystemWarmedUp: Bool = {
        LillistFonts.registerIfNeeded()
        let probe = VStack {
            ForEach(Array(warmupFonts.enumerated()), id: \.offset) { _, font in
                Text(verbatim: "Sphinx of black quartz…").font(font)
            }
        }
        let size = CGSize(width: 300, height: 400)
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let host = NSHostingView(rootView: probe)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        if let rep { host.cacheDisplay(in: host.bounds, to: rep) }
        #elseif canImport(UIKit)
        let host = UIHostingController(rootView: probe)
        host.view.frame = CGRect(origin: .zero, size: size)
        UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        #endif
        return true
    }()

    private static let warmupFonts: [Font] = [
        LillistTypography.largeTitle, LillistTypography.title,
        LillistTypography.title2, LillistTypography.title3,
        LillistTypography.headline, LillistTypography.body,
        LillistTypography.subheadline, LillistTypography.caption,
        LillistTypography.caption2, LillistTypography.quickCaptureField,
    ]

    override func invokeTest() {
        // XCTest invokes tests on the main thread; hop into MainActor
        // statically for the AppKit/UIKit hosting warm-up.
        MainActor.assumeIsolated { _ = Self.textSystemWarmedUp }
        if Self.isRecordRun {
            withSnapshotTesting(record: .all) { super.invokeTest() }
        } else {
            super.invokeTest()
        }
    }
}
