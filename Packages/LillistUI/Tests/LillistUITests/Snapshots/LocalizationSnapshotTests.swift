#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

/// Render LillistUI atoms under right-to-left layout and Arabic locale.
///
/// Plan 17 doesn't ship a second locale — these snapshots lock the *shape*
/// of each view (mirrored layout, no clipping, no overflow) so that a
/// future locale is a content swap rather than a layout rewrite.
///
/// The English-LTR baselines for these atoms live in adjacent snapshot
/// files (TaskListView, SidebarView, QuickCaptureView snapshot suites).
/// This file adds the RTL + Arabic variants only.
@MainActor
final class LocalizationSnapshotTests: XCTestCase {
    func test_breadcrumbView_rtl() {
        let view = BreadcrumbView(path: ["Work", "Lillist", "Plan 17"])
            .environment(\.layoutDirection, .rightToLeft)
            .frame(width: 320, height: 32)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 320, height: 60)),
                       as: .image(precision: 0.99),
                       named: "breadcrumb-rtl")
    }

    func test_breadcrumbView_ar() {
        let view = BreadcrumbView(path: ["Work", "Lillist", "Plan 17"])
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .frame(width: 320, height: 32)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 320, height: 60)),
                       as: .image(precision: 0.99),
                       named: "breadcrumb-ar")
    }

    func test_taskRowView_rtl() {
        let task = TaskStore.TaskRecord(
            id: UUID(), title: "Buy milk", notes: "",
            status: .todo, start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false, position: 0,
            isPinned: false, parentID: nil, createdAt: Date(),
            modifiedAt: Date(), closedAt: nil, deletedAt: nil,
            seriesID: nil
        )
        let view = TaskRowView(task: task, tagNames: ["work"],
                               onStatusClick: {}, onStatusLongPress: {})
            .environment(\.layoutDirection, .rightToLeft)
            .frame(width: 380, height: 44)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 380, height: 80)),
                       as: .image(precision: 0.99),
                       named: "taskrow-rtl")
    }

    func test_recurrenceEditor_ar() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .weekly
        vm.byDay = [.tuesday, .thursday]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 420, height: 600)),
                       as: .image(precision: 0.99),
                       named: "recurrence-weekly-ar")
    }

    func test_quickCaptureView_rtl() {
        let view = StatefulQuickCapture(text: "Ship release #work ^tomorrow")
            .environment(\.layoutDirection, .rightToLeft)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 560, height: 140)),
                       as: .image(precision: 0.99),
                       named: "quickcapture-rtl")
    }

    private struct StatefulQuickCapture: View {
        @State var text: String
        var body: some View {
            QuickCaptureView(text: $text, onSubmit: { _ in }, onCancel: {})
        }
    }
}
#endif
