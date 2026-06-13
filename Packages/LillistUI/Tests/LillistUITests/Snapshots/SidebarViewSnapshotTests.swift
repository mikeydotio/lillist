#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

@MainActor
final class SidebarComponentsSnapshotTests: RecordableSnapshotTestCase {
    func test_sidebarRow_task_light() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                SidebarRowView(icon: "circle", label: "Buy milk", kind: .task)
                    .padding().frame(width: 240)
            },
            size: CGSize(width: 240, height: 44)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 240, height: 44)))
    }

    func test_sidebarRow_smartFilter_with_badge_dark() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .dark) {
                SidebarRowView(icon: "line.3.horizontal.decrease.circle", label: "Today", badge: 12, kind: .smartFilter)
                    .padding().frame(width: 240)
            },
            size: CGSize(width: 240, height: 44)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 240, height: 44)))
    }

    func test_sidebarRow_trash_with_badge_light() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                SidebarRowView(icon: "trash", label: "Trash", badge: 3, kind: .trash)
                    .padding().frame(width: 240)
            },
            size: CGSize(width: 240, height: 44)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 240, height: 44)))
    }

    func test_syncDot_idle_recent() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                SyncStatusDotView(indicator: .idle(lastSync: Date(timeIntervalSince1970: 1_780_000_000)), onRetry: {}).padding()
            },
            size: CGSize(width: 60, height: 40)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    func test_syncDot_error() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                SyncStatusDotView(indicator: .error(message: "Auth failed", lastSuccess: nil), onRetry: {}).padding()
            },
            size: CGSize(width: 60, height: 40)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }
}
#endif
