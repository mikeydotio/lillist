#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

/// Locks the visual contrast tuning under "Increase Contrast". Uses the
/// internal `increaseContrastOverride` env key — SDK 26.2 exposes the
/// system `colorSchemeContrast` keypath as read-only, so a snapshot
/// can't directly inject the system setting. The override key gives
/// snapshot tests a deterministic way to drive the increase-contrast
/// code path; production code consults the system value as usual.
@MainActor
final class ContrastSnapshotTests: XCTestCase {
    func test_tagChip_normal() {
        let view = HStack {
            TagChipView(name: "work", tint: TagTint(hex: "#3478F6"))
            TagChipView(name: "urgent", tint: TagTint(hex: "#FF3B30"))
        }
        .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 240, height: 60)),
                       as: .image(precision: 0.99),
                       named: "tagchip-normal")
    }

    func test_tagChip_increaseContrast() {
        let view = HStack {
            TagChipView(name: "work", tint: TagTint(hex: "#3478F6"))
            TagChipView(name: "urgent", tint: TagTint(hex: "#FF3B30"))
        }
        .padding()
        .environment(\.increaseContrastOverride, true)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 240, height: 60)),
                       as: .image(precision: 0.99),
                       named: "tagchip-increase-contrast")
    }

    func test_tagChip_dark_increaseContrast() {
        let view = HStack {
            TagChipView(name: "work", tint: TagTint(hex: "#3478F6"))
        }
        .padding()
        .environment(\.colorScheme, .dark)
        .environment(\.increaseContrastOverride, true)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 160, height: 60)),
                       as: .image(precision: 0.99),
                       named: "tagchip-dark-increase-contrast")
    }
}
#endif
