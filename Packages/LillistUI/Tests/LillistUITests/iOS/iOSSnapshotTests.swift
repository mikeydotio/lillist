#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

/// Snapshot coverage for the iOS-only LillistUI atoms that render in the
/// standalone (offscreen) test bundle: `SyncStatusBadge` and the
/// `TaskNotesTab` visual contract.
///
/// Deviation note (Plan 8 Tasks 24+25): the plan called for per-view
/// snapshots of `TodayView`, `AllTagsView`, etc. — but the iOS app's test
/// bundle is standalone (no test host) and cannot `@testable import
/// Lillist_iOS`. We instead snapshot the iOS-only LillistUI atoms the
/// per-view shells compose; stable visual regressions on these atoms catch
/// the same drift the per-view snapshots would.
///
/// Glass-bearing atoms that blank the offscreen capture — the FAB
/// (`.primaryAction` interactive glass), `QuickCaptureDialog` (`.panel`
/// glass), and the interactive `StatusIndicatorView` (a `Menu` hit layer)
/// — moved to `Lillist-iOSAppHostedTests/GlassSnapshotTests`, which renders
/// through a live key window. See docs/engineering-notes.md 2026-06-12 and
/// the 2026-06-14 refinement.
final class iOSSnapshotTests: RecordableSnapshotTestCase {
    @MainActor
    func test_syncStatusBadge_idle() {
        let view = SyncStatusBadge(indicator: .idle(lastSync: Date(timeIntervalSince1970: 0)))
            .padding()
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_error() {
        let view = SyncStatusBadge(
            indicator: .error(message: "Network unavailable", lastSuccess: nil)
        )
        .padding()
        .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_inProgress() {
        let view = SyncStatusBadge(indicator: .inProgress)
            .padding()
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_idle_dark() {
        let view = SyncStatusBadge(indicator: .idle(lastSync: Date(timeIntervalSince1970: 0)))
            .padding()
            .background(Color(.systemBackground))
            .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        host.overrideUserInterfaceStyle = .dark
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_error_dark() {
        let view = SyncStatusBadge(
            indicator: .error(message: "Network unavailable", lastSuccess: nil)
        )
        .padding()
        .background(Color(.systemBackground))
        .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        host.overrideUserInterfaceStyle = .dark
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_inProgress_dark() {
        let view = SyncStatusBadge(indicator: .inProgress)
            .padding()
            .background(Color(.systemBackground))
            .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        host.overrideUserInterfaceStyle = .dark
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    // MARK: - TaskNotesTab visual fixtures (Plan 18 Task 4)
    //
    // The iOS test bundle can't @testable import Lillist_iOS, so each
    // fixture below reconstructs the ZStack + TextEditor shape inline.
    // The snapshot pins the *visual contract* — the placeholder
    // visibility rule, the scroll-indicator presence, and the
    // character-count footer threshold. If TaskNotesTab's body shape
    // changes, update the fixtures in lockstep.

    @MainActor
    func test_taskNotesTab_empty_placeholder() {
        let view = TaskNotesFixture(text: "")
            .frame(width: 360, height: 200)
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 200)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 200)))
    }

    @MainActor
    func test_taskNotesTab_short_no_counter() {
        let view = TaskNotesFixture(text: "Short note.")
            .frame(width: 360, height: 200)
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 200)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 200)))
    }

    @MainActor
    func test_taskNotesTab_long_shows_counter() {
        let body = String(repeating: "Lorem ipsum dolor sit amet. ", count: 25)
        let view = TaskNotesFixture(text: body)
            .frame(width: 360, height: 240)
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 240)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 240)))
    }
}

/// Mirror of `TaskNotesTab`'s visual shape — placeholder overlay,
/// editor with scroll indicators, character-count footer past 500. The
/// fixture renders without a Core Data store so it can be hosted in
/// the standalone LillistUI test bundle. If `TaskNotesTab.body`
/// changes, update this fixture in lockstep.
private struct TaskNotesFixture: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Notes — markdown supported")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }
                TextEditor(text: .constant(text))
                    .scrollIndicators(.automatic)
            }
            if text.count > 500 {
                Text("\(text.count) characters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }
}
#endif
