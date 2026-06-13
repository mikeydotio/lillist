#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI
import LillistCore

/// Visual baselines for the Rainbow Logic status cube: every status in
/// both schemes, the increase-contrast variants, and the row context.
/// All fixtures render the settled (idle) state — a confetti burst can
/// only exist within 650 ms of a live transition, so these baselines
/// are deterministic by construction.
final class StatusCubeSnapshotTests: RecordableSnapshotTestCase {

    @MainActor
    private func cubeGallery(scheme: ColorScheme) -> NSView {
        let view = HStack(spacing: 16) {
            ForEach(Status.allCases, id: \.self) { status in
                StatusCubeView(status: status)
            }
        }
        .padding(20)
        .background(LillistColor.workspace)
        .environment(\.colorScheme, scheme)
        return makeHostingView(view, size: CGSize(width: 220, height: 70))
    }

    @MainActor
    func test_cubes_all_statuses_light() {
        assertSnapshot(of: cubeGallery(scheme: .light), as: .image(size: CGSize(width: 220, height: 70)))
    }

    @MainActor
    func test_cubes_all_statuses_dark() {
        assertSnapshot(of: cubeGallery(scheme: .dark), as: .image(size: CGSize(width: 220, height: 70)))
    }

    @MainActor
    func test_cubes_increase_contrast_light() {
        let view = HStack(spacing: 16) {
            ForEach(Status.allCases, id: \.self) { status in
                StatusCubeView(status: status)
            }
        }
        .padding(20)
        .background(LillistColor.workspace)
        .environment(\.colorScheme, .light)
        .environment(\.increaseContrastOverride, true)
        let host = makeHostingView(view, size: CGSize(width: 220, height: 70))
        assertSnapshot(of: host, as: .image(size: CGSize(width: 220, height: 70)))
    }

    /// A closed cube rendered at rest — guards that no confetti remnant
    /// ever appears in a static render.
    @MainActor
    func test_closed_cube_idle_no_confetti() {
        let view = StatusCubeView(status: .closed)
            .padding(24)
            .background(LillistColor.card)
            .environment(\.colorScheme, .light)
        let host = makeHostingView(view, size: CGSize(width: 72, height: 72))
        assertSnapshot(of: host, as: .image(size: CGSize(width: 72, height: 72)))
    }
}
#endif
