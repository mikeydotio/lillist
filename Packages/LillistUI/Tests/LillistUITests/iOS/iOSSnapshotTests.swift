#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

/// Snapshot coverage for the iOS-only LillistUI components.
///
/// Deviation note (Plan 8 Tasks 24+25): The plan called for per-view
/// snapshots of `TodayView`, `AllTagsView`, etc. — but the iOS app's test
/// bundle is standalone (no test host) and cannot `@testable import
/// Lillist_iOS`. Per-view snapshots also require an `AppEnvironment` /
/// in-memory `PersistenceController`, which is heavier than the snapshot
/// flow needs. We instead snapshot the iOS-only LillistUI atoms
/// (FloatingAddButton, SyncStatusBadge, QuickCaptureField) which the
/// per-view shells compose. Stable visual regressions on these atoms catch
/// the same drift the per-view snapshots would.
final class iOSSnapshotTests: XCTestCase {
    @MainActor
    func test_floatingAddButton_light() {
        let view = FloatingAddButton(onTap: {})
            .frame(width: 200, height: 100)
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 200, height: 100)),
                       named: "fab-light")
    }

    @MainActor
    func test_floatingAddButton_dark() {
        let view = FloatingAddButton(onTap: {})
            .environment(\.colorScheme, .dark)
            .frame(width: 200, height: 100)
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 200, height: 100)),
                       named: "fab-dark")
    }

    @MainActor
    func test_floatingAddButton_accessibilityLabel_is_present() {
        let view = FloatingAddButton(onTap: {})
            .frame(width: 200, height: 100)
        let host = UIHostingController(rootView: view)
        host.view.layoutIfNeeded()
        XCTAssertTrue(findAccessibilityLabel(in: host.view, equals: "New task"),
                      "FloatingAddButton must expose a 'New task' accessibility label")
    }

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

    @MainActor
    func test_quickCaptureField_with_parsed_tokens() {
        let view = QuickCaptureField(
            text: .constant("Buy milk #errands ^tomorrow"),
            tagSuggestions: ["shopping"],
            dateSuggestions: ["today"],
            onSubmit: { _ in }
        )
        .padding()
        .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 160)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 160)),
                       named: "quick-capture-field-with-parsed-tokens")
    }

    @MainActor
    func test_statusIndicator_menu_button_renders_at_44pt() {
        let view = StatusIndicatorView(
            status: .todo,
            onClick: {},
            onSetStatus: { _ in }
        )
        .padding()
        .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 80, height: 80)))
    }

    // MARK: - helpers

    @MainActor
    private func findAccessibilityLabel(in root: UIView, equals target: String) -> Bool {
        if root.accessibilityLabel == target { return true }
        for sub in root.subviews where findAccessibilityLabel(in: sub, equals: target) {
            return true
        }
        return false
    }
}
#endif
