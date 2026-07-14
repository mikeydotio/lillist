#if os(macOS)
import XCTest
import SnapshotTesting
import SwiftUI
import LillistCore
@testable import LillistUI

/// Image snapshots for `WidgetFilterCardView` across the system families and a
/// few content states (populated, empty, long-title truncation) in light + dark.
/// Baselines land under `Widgets/__Snapshots__/WidgetFilterCardSnapshotTests/`.
///
/// `precision: 0.99 / perceptualPrecision: 0.98` matches the other suites —
/// allows sub-pixel AA drift while catching real layout regressions.
@MainActor
final class WidgetFilterCardSnapshotTests: RecordableSnapshotTestCase {
    // Approximate iPhone widget point sizes.
    private let smallSize = CGSize(width: 170, height: 170)
    private let mediumSize = CGSize(width: 364, height: 170)
    private let largeSize = CGSize(width: 364, height: 382)

    private func fixture(
        name: String = "Todayish",
        tint: String? = "#8B45E8",
        rows: [(String, Status)],
        total: Int? = nil
    ) -> WidgetSnapshot {
        let taskRows = rows.map { WidgetSnapshot.Row(id: UUID(), title: $0.0, status: $0.1) }
        let open = taskRows.filter { $0.status.isClosed == false }.count
        return WidgetSnapshot(
            filterID: UUID(),
            filterName: name,
            tintHex: tint,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            totalCount: total ?? taskRows.count,
            openCount: open,
            tasks: taskRows
        )
    }

    private var referenceRows: [(String, Status)] {
        [
            ("Submit feedback", .todo),
            ("Custom router bit", .started),
            ("Renew passport", .todo),
            ("Gather info for Chris Rodriquez", .todo),
            ("Gather Meds/Diagnosis info", .todo),
            ("Docs for Toni", .blocked),
            ("Vehicle registration", .todo),
            ("Vax records for Lana", .closed),
        ]
    }

    private func assertCard(
        _ snapshot: WidgetSnapshot,
        layout: WidgetLayout,
        scheme: ColorScheme,
        size: CGSize,
        named name: String
    ) {
        let view = WidgetFilterCardView(snapshot: snapshot, layout: layout)
            // The widget supplies a container shape at runtime; offscreen there
            // is none, so pin one that mimics a widget's rounded corners — the
            // card's `ContainerRelativeShape` border/fill resolve against it.
            .containerShape(RoundedRectangle(cornerRadius: LillistRadius.xl, style: .continuous))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: size.width, height: size.height)
        assertSnapshot(
            of: makeHostingView(view, size: size),
            as: .image(precision: 0.99, perceptualPrecision: 0.98),
            named: name
        )
    }

    func testLarge_dark() {
        assertCard(fixture(rows: referenceRows, total: 12), layout: .large, scheme: .dark, size: largeSize, named: "large-dark")
    }

    func testLarge_light() {
        assertCard(fixture(rows: referenceRows, total: 12), layout: .large, scheme: .light, size: largeSize, named: "large-light")
    }

    func testMedium_dark() {
        assertCard(fixture(rows: Array(referenceRows.prefix(3)), total: 8), layout: .medium, scheme: .dark, size: mediumSize, named: "medium-dark")
    }

    func testSmall_dark() {
        assertCard(fixture(rows: Array(referenceRows.prefix(3)), total: 8), layout: .small, scheme: .dark, size: smallSize, named: "small-dark")
    }

    func testEmpty_dark() {
        assertCard(fixture(rows: [], total: 0), layout: .large, scheme: .dark, size: largeSize, named: "empty-dark")
    }

    func testLongTitle_dark() {
        let rows: [(String, Status)] = [
            ("Coordinate the cross-functional quarterly planning offsite logistics", .todo),
            ("Short one", .todo),
        ]
        assertCard(fixture(rows: rows, total: 2), layout: .large, scheme: .dark, size: largeSize, named: "long-title-dark")
    }

    /// A long title on the **last** visible row of a *filled* card — the only
    /// row that shares the "+" overlay's horizontal band — must truncate clear
    /// of the glyph. Uses medium, whose 4-row fill packs the last row directly
    /// beside the bottom-trailing "+", so the `trailingInset(isLast:)` collision
    /// fix is actually exercised (at large the rows don't reach the glyph).
    func testLongTitleLastRow_dark() {
        let rows: [(String, Status)] = Array(referenceRows.prefix(3)) + [
            ("Coordinate the cross-functional quarterly planning offsite logistics", .todo),
        ]
        assertCard(fixture(rows: rows, total: 4), layout: .medium, scheme: .dark, size: mediumSize, named: "long-title-last-row-dark")
    }

    /// Medium filled to its new cap (4 rows) verifies the reclaimed footer band
    /// shows the extra row without clipping at the fixed 364×170 medium size.
    func testMediumFull_dark() {
        assertCard(fixture(rows: Array(referenceRows.prefix(4)), total: 9), layout: .medium, scheme: .dark, size: mediumSize, named: "medium-full-dark")
    }

    /// Large filled to its new cap (9 rows) verifies the reclaimed footer band
    /// shows the extra row without clipping at the fixed 364×382 large size.
    func testLargeFull_dark() {
        let rows: [(String, Status)] = Array(referenceRows.prefix(7)) + [
            ("Order replacement filters", .todo),
            ("Schedule dentist visit", .todo),
        ]
        assertCard(fixture(rows: rows, total: 14), layout: .large, scheme: .dark, size: largeSize, named: "large-full-dark")
    }
}
#endif
