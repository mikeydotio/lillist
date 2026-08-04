import Testing
import Foundation
import LillistCore
@testable import LillistUI

/// `LIL-96`: ``WidgetDonutModel`` — the pure arc math behind the `systemSmall`
/// status donut. Platform-agnostic; no rendering involved.
@Suite("WidgetDonutModel")
struct WidgetDonutModelTests {
    private func snapshot(
        totalCount: Int,
        openCount: Int,
        statusCounts: WidgetSnapshot.StatusCounts?,
        isUnfiltered: Bool = false
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            filterID: isUnfiltered ? WidgetSnapshot.unfilteredID : UUID(),
            filterName: "Todayish",
            tintHex: "#8B45E8",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            totalCount: totalCount,
            openCount: openCount,
            statusCounts: statusCounts,
            tasks: []
        )
    }

    @Test("segments are contiguous: start at 0, no gaps, end at exactly 1.0")
    func segmentsAreContiguous() {
        let counts = WidgetSnapshot.StatusCounts(todo: 3, started: 1, blocked: 1, closed: 4)
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 9, openCount: 5, statusCounts: counts))

        #expect(plan.segments.first?.start == 0)
        #expect(plan.segments.last?.end == 1.0)
        for (a, b) in zip(plan.segments, plan.segments.dropFirst()) {
            #expect(a.end == b.start, "no gaps between adjacent segments")
        }
    }

    @Test("zero-count statuses produce no segment")
    func zeroCountStatusesOmitted() {
        let counts = WidgetSnapshot.StatusCounts(todo: 3, started: 0, blocked: 0, closed: 4)
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 7, openCount: 3, statusCounts: counts))

        #expect(plan.segments.map(\.kind) == [.status(.todo), .status(.closed)])
    }

    @Test("segments are ordered todo, started, blocked, closed")
    func segmentsAreOrderedByStatusRawValue() {
        let counts = WidgetSnapshot.StatusCounts(todo: 1, started: 1, blocked: 1, closed: 1)
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 4, openCount: 3, statusCounts: counts))

        #expect(plan.segments.map(\.kind) == [.status(.todo), .status(.started), .status(.blocked), .status(.closed)])
    }

    @Test("a single non-zero status produces one full-ring segment")
    func singleStatusProducesFullRing() {
        let counts = WidgetSnapshot.StatusCounts(todo: 0, started: 0, blocked: 0, closed: 5)
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 5, openCount: 0, statusCounts: counts))

        #expect(plan.segments.count == 1)
        #expect(plan.segments[0].start == 0)
        #expect(plan.segments[0].end == 1.0)
    }

    @Test("an all-zero statusCounts (totalCount == 0) produces no segments")
    func zeroTotalProducesNoSegments() {
        let counts = WidgetSnapshot.StatusCounts(todo: 0, started: 0, blocked: 0, closed: 0)
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 0, openCount: 0, statusCounts: counts))

        #expect(plan.segments.isEmpty)
        #expect(plan.openCount == 0)
    }

    @Test("a legacy snapshot (nil statusCounts) with a mix produces exactly unspecifiedOpen + closed, legend hidden")
    func legacyMixProducesTwoSegmentsNoLegend() {
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 9, openCount: 5, statusCounts: nil))

        #expect(plan.segments.map(\.kind) == [.unspecifiedOpen, .status(.closed)])
        #expect(plan.segments[0].count == 5)
        #expect(plan.segments[1].count == 4)
        #expect(plan.openCount == 5)
        #expect(plan.showsLegend == false)
    }

    @Test("a legacy snapshot with everything open produces exactly one unspecifiedOpen segment")
    func legacyAllOpenProducesOneSegment() {
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 4, openCount: 4, statusCounts: nil))

        #expect(plan.segments.map(\.kind) == [.unspecifiedOpen])
        #expect(plan.segments[0].start == 0)
        #expect(plan.segments[0].end == 1.0)
    }

    @Test("a legacy snapshot with everything closed produces exactly one closed segment")
    func legacyAllClosedProducesOneSegment() {
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 4, openCount: 0, statusCounts: nil))

        #expect(plan.segments.map(\.kind) == [.status(.closed)])
    }

    @Test("with statusCounts present, showsLegend is true even for a single-status filter")
    func showsLegendTrueWhenStatusCountsPresent() {
        let counts = WidgetSnapshot.StatusCounts(todo: 5, started: 0, blocked: 0, closed: 0)
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 5, openCount: 5, statusCounts: counts))

        #expect(plan.showsLegend == true)
    }

    @Test("a statusCounts total disagreeing with totalCount is resolved in favor of statusCounts")
    func statusCountsWinsOverDisagreeingTotalCount() {
        // Pathological input: totalCount says 100, but statusCounts (the
        // finer-grained field) only tallies 4. The plan must use the field
        // that actually backs the segments, not the stale/wrong scalar.
        let counts = WidgetSnapshot.StatusCounts(todo: 2, started: 0, blocked: 0, closed: 2)
        let plan = WidgetDonutModel.plan(for: snapshot(totalCount: 100, openCount: 100, statusCounts: counts))

        #expect(plan.segments.last?.end == 1.0, "denominator must be statusCounts.total (4), not totalCount (100)")
        #expect(plan.openCount == 2, "center count must be statusCounts.open, not the disagreeing snapshot.openCount")
    }
}
