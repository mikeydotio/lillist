#if os(macOS)
import XCTest
import SnapshotTesting
import SwiftUI
import LillistCore
@testable import LillistUI

/// Image snapshots for `RecurrenceEditorView` covering empty/light, empty/dark,
/// weekly-with-byDay, and after-completion modes. Baselines land alongside this
/// file under `Recurrence/__Snapshots__/RecurrenceEditorSnapshotTests/`.
///
/// `precision` allows up to 1% of pixels to mismatch outright (catches real
/// layout regressions). `perceptualPrecision` lets sub-pixel/AA-edge drift on
/// the remaining pixels still count as a match (suppresses the cold-cache
/// font-rendering flake that SwiftUI `Form` is uniquely prone to). The pair
/// is the swift-snapshot-testing-recommended setting for AppKit Form views;
/// see engineering-notes.md for the incident that introduced it.
@MainActor
final class RecurrenceEditorSnapshotTests: XCTestCase {
    func testEmptyState_light() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 320)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 320)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.98),
                       named: "empty-light")
    }

    func testEmptyState_dark() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .environment(\.colorScheme, .dark)
            .frame(width: 420, height: 320)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 320)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.98),
                       named: "empty-dark")
    }

    func testWeeklyTuesdayThursday_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .weekly
        vm.byDay = [.tuesday, .thursday]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 600)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.98),
                       named: "weekly-tuth-light")
    }

    func testAfterCompletion_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.mode = .afterCompletion
        vm.afterCompletionSeconds = 86_400 * 7
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 360)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 360)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.98),
                       named: "after-completion-week-light")
    }

    func testMonthlyDay15_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .monthly
        vm.byMonthDay = [15]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 600)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.98),
                       named: "monthly-day-15-light")
    }

    func testMonthlyMultipleDays_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .monthly
        vm.byMonthDay = [1, 7, 15, 22, 28]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 600)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.98),
                       named: "monthly-multi-light")
    }
}
#endif
