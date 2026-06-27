import XCTest
import LillistCore
@testable import LillistUI

/// Pins the single-presentation router that replaced the stacked
/// `.sheet`/`.fullScreenCover` modifiers in `ICloudSyncSection` (iOS) and
/// `ICloudSyncPane` (macOS) — the stack that flashed the Disable sheet and tore
/// down the Settings pane. The view glue isn't unit-testable, but the routing
/// decisions are, and they're shared verbatim by both platforms.
final class SyncSheetRouteTests: XCTestCase {
    func test_afterToggle_off_opensDisable() {
        XCTAssertEqual(SyncSheetRoute.afterToggle(on: false), .disable)
    }

    func test_afterToggle_on_opensChoice() {
        XCTAssertEqual(SyncSheetRoute.afterToggle(on: true), .choice)
    }

    /// The `.progress` id is deliberately constant across phases so streaming a
    /// new phase updates the presented sheet *in place* instead of dismissing
    /// and re-presenting it on every progress tick.
    func test_progress_id_isConstant_acrossPhases() {
        XCTAssertEqual(SyncSheetRoute.progress(.preparing).id, "progress")
        XCTAssertEqual(SyncSheetRoute.progress(.completed).id, "progress")
        XCTAssertEqual(SyncSheetRoute.progress(.uploading(progress: 0.5)).id, "progress")
        XCTAssertEqual(SyncSheetRoute.progress(.failed(reason: "boom")).id, "progress")
    }

    func test_caseIds_areDistinct() {
        let ids = Set([
            SyncSheetRoute.choice.id,
            SyncSheetRoute.disable.id,
            SyncSheetRoute.pauseExplainer.id,
            SyncSheetRoute.progress(.preparing).id,
        ])
        XCTAssertEqual(ids.count, 4, "Each non-progress modal needs its own id for clean slot swaps")
    }

    /// Same id (so the sheet stays presented) but distinct values (so SwiftUI
    /// re-renders the content with the new phase). Both halves matter.
    func test_progress_sharesId_butDistinguishesPhases() {
        XCTAssertEqual(SyncSheetRoute.progress(.preparing).id, SyncSheetRoute.progress(.completed).id)
        XCTAssertNotEqual(SyncSheetRoute.progress(.preparing), SyncSheetRoute.progress(.completed))
    }
}
