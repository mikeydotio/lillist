#if os(macOS)
import XCTest
import SnapshotTesting
import SwiftUI
import LillistCore
@testable import LillistUI

/// `LIL-96`: image snapshots for `WidgetStatusDonutView`, the `.systemSmall`
/// status donut. Baselines land under
/// `Widgets/__Snapshots__/WidgetStatusDonutSnapshotTests/`.
@MainActor
final class WidgetStatusDonutSnapshotTests: RecordableSnapshotTestCase {
    // Approximate iPhone systemSmall widget point size.
    private let smallSize = CGSize(width: 170, height: 170)

    private func fixture(
        name: String = "Todayish",
        totalCount: Int,
        openCount: Int,
        statusCounts: WidgetSnapshot.StatusCounts?,
        isUnfiltered: Bool = false
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            filterID: isUnfiltered ? WidgetSnapshot.unfilteredID : UUID(),
            filterName: name,
            tintHex: "#8B45E8",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            totalCount: totalCount,
            openCount: openCount,
            statusCounts: statusCounts,
            tasks: []
        )
    }

    private func assertDonut(
        _ snapshot: WidgetSnapshot,
        scheme: ColorScheme,
        named name: String
    ) {
        let view = WidgetStatusDonutView(snapshot: snapshot)
            // The widget supplies a container shape at runtime; offscreen there
            // is none, so pin one that mimics a widget's rounded corners — same
            // rationale as WidgetFilterCardSnapshotTests.
            .containerShape(RoundedRectangle(cornerRadius: LillistRadius.xl, style: .continuous))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: smallSize.width, height: smallSize.height)
        assertSnapshot(
            of: makeHostingView(view, size: smallSize),
            as: .image(precision: 0.99, perceptualPrecision: 0.98),
            named: name
        )
    }

    func testMixed_dark() {
        let counts = WidgetSnapshot.StatusCounts(todo: 3, started: 1, blocked: 1, closed: 4)
        assertDonut(fixture(totalCount: 9, openCount: 5, statusCounts: counts), scheme: .dark, named: "mixed-dark")
    }

    func testMixed_light() {
        let counts = WidgetSnapshot.StatusCounts(todo: 3, started: 1, blocked: 1, closed: 4)
        assertDonut(fixture(totalCount: 9, openCount: 5, statusCounts: counts), scheme: .light, named: "mixed-light")
    }

    func testAllDone_dark() {
        let counts = WidgetSnapshot.StatusCounts(todo: 0, started: 0, blocked: 0, closed: 6)
        assertDonut(fixture(totalCount: 6, openCount: 0, statusCounts: counts), scheme: .dark, named: "all-done-dark")
    }

    func testAllTodo_dark() {
        let counts = WidgetSnapshot.StatusCounts(todo: 5, started: 0, blocked: 0, closed: 0)
        assertDonut(fixture(totalCount: 5, openCount: 5, statusCounts: counts), scheme: .dark, named: "all-todo-dark")
    }

    func testEmpty_dark() {
        let counts = WidgetSnapshot.StatusCounts(todo: 0, started: 0, blocked: 0, closed: 0)
        assertDonut(fixture(totalCount: 0, openCount: 0, statusCounts: counts), scheme: .dark, named: "empty-dark")
    }

    /// A cache written before `LIL-96` — `statusCounts == nil` — degrades to
    /// the two-segment open/closed split with the legend suppressed.
    func testLegacy_dark() {
        assertDonut(fixture(totalCount: 9, openCount: 5, statusCounts: nil), scheme: .dark, named: "legacy-dark")
    }

    func testLongName_dark() {
        let counts = WidgetSnapshot.StatusCounts(todo: 2, started: 0, blocked: 0, closed: 1)
        assertDonut(
            fixture(
                name: "Cross-functional quarterly planning offsite logistics",
                totalCount: 3,
                openCount: 2,
                statusCounts: counts
            ),
            scheme: .dark,
            named: "long-name-dark"
        )
    }

    /// A 3-digit remaining count must not overflow the ring's center — the
    /// motivation for `minimumScaleFactor` on the center label.
    func testThreeDigit_dark() {
        let counts = WidgetSnapshot.StatusCounts(todo: 120, started: 0, blocked: 0, closed: 4)
        assertDonut(fixture(totalCount: 124, openCount: 120, statusCounts: counts), scheme: .dark, named: "three-digit-dark")
    }

    /// The "No Filter" sentinel has no filter name to show — the title row is
    /// hidden entirely, matching `WidgetHeaderView`'s `isUnfiltered` rule.
    func testUnfiltered_dark() {
        let counts = WidgetSnapshot.StatusCounts(todo: 2, started: 1, blocked: 0, closed: 3)
        assertDonut(
            fixture(totalCount: 6, openCount: 3, statusCounts: counts, isUnfiltered: true),
            scheme: .dark,
            named: "unfiltered-dark"
        )
    }
}
#endif
