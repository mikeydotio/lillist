#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

@MainActor
final class TaskDetailComponentsSnapshotTests: XCTestCase {
    func test_tagChip_with_tint_light() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                HStack {
                    TagChipView(name: "work", tint: TagTint(hex: "#3366FF"))
                    TagChipView(name: "personal", tint: TagTint(hex: "#FF6644"))
                    TagChipView(name: "no-tint")
                }
                .padding()
            },
            size: CGSize(width: 360, height: 50)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 50)))
    }

    func test_tagChip_with_tint_dark_desaturated() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .dark) {
                HStack {
                    TagChipView(name: "work", tint: TagTint(hex: "#3366FF"))
                    TagChipView(name: "personal", tint: TagTint(hex: "#FF6644"))
                }
                .padding()
            },
            size: CGSize(width: 360, height: 50)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 50)))
    }
}
#endif
