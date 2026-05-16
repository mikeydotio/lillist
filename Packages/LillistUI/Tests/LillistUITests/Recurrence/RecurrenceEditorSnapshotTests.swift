#if os(macOS)
import XCTest
import SnapshotTesting
import SwiftUI
import LillistCore
@testable import LillistUI

/// Image snapshots for `RecurrenceEditorView` covering empty/light, empty/dark,
/// weekly-with-byDay, and after-completion modes. Baselines land alongside this
/// file under `Recurrence/__Snapshots__/RecurrenceEditorSnapshotTests/`.
@MainActor
final class RecurrenceEditorSnapshotTests: XCTestCase {
    func testEmptyState_light() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 320)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 320)),
                       as: .image(precision: 0.99), named: "empty-light")
    }

    func testEmptyState_dark() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .environment(\.colorScheme, .dark)
            .frame(width: 420, height: 320)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 320)),
                       as: .image(precision: 0.99), named: "empty-dark")
    }

    func testWeeklyTuesdayThursday_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .weekly
        vm.byDay = [.tuesday, .thursday]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 600)),
                       as: .image(precision: 0.99), named: "weekly-tuth-light")
    }

    func testAfterCompletion_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.mode = .afterCompletion
        vm.afterCompletionSeconds = 86_400 * 7
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 360)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 360)),
                       as: .image(precision: 0.99), named: "after-completion-week-light")
    }
}
#endif
