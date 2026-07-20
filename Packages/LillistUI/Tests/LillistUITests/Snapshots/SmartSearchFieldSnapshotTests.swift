#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

/// Visual baselines for the agentic-search affordance (issue #51): the
/// smart-search toggle plus its status strip across every `SmartSearchState`.
/// Mock-driven — no live translator involved, since these states are only
/// ever entered by the host's own logic, never by SwiftUI itself.
final class SmartSearchFieldSnapshotTests: RecordableSnapshotTestCase {
    private let size = CGSize(width: 340, height: 90)

    @MainActor
    private func host(isAvailable: Bool, isSmartMode: Bool, state: SmartSearchState) -> NSView {
        let view = SnapshotHost(colorScheme: .light) {
            SmartSearchField(
                isAvailable: isAvailable,
                isSmartMode: .constant(isSmartMode),
                state: state
            )
            .padding(12)
        }
        return makeHostingView(view, size: size)
    }

    @MainActor
    func test_unavailable_rendersNothing() {
        assertSnapshot(of: host(isAvailable: false, isSmartMode: false, state: .idle), as: .image(size: size))
    }

    @MainActor
    func test_available_toggleOff() {
        assertSnapshot(of: host(isAvailable: true, isSmartMode: false, state: .idle), as: .image(size: size))
    }

    @MainActor
    func test_available_toggleOn_idle() {
        assertSnapshot(of: host(isAvailable: true, isSmartMode: true, state: .idle), as: .image(size: size))
    }

    @MainActor
    func test_translating() {
        assertSnapshot(of: host(isAvailable: true, isSmartMode: true, state: .translating), as: .image(size: size))
    }

    @MainActor
    func test_translated_withExplanation() {
        let state = SmartSearchState.translated(
            explanation: "deadline before today and status is not closed",
            unmappedTerms: []
        )
        assertSnapshot(of: host(isAvailable: true, isSmartMode: true, state: state), as: .image(size: size))
    }

    @MainActor
    func test_translated_withUnmappedTerms() {
        let state = SmartSearchState.translated(
            explanation: "title contains “report”",
            unmappedTerms: ["tag “Ghost”", "recurrence is"]
        )
        assertSnapshot(of: host(isAvailable: true, isSmartMode: true, state: state), as: .image(size: size))
    }

    @MainActor
    func test_translated_couldNotUnderstand() {
        let state = SmartSearchState.translated(explanation: nil, unmappedTerms: [])
        assertSnapshot(of: host(isAvailable: true, isSmartMode: true, state: state), as: .image(size: size))
    }

    @MainActor
    func test_failed() {
        let state = SmartSearchState.failed(message: "Smart search failed: quota exceeded.")
        assertSnapshot(of: host(isAvailable: true, isSmartMode: true, state: state), as: .image(size: size))
    }

    @MainActor
    func test_unsupported() {
        assertSnapshot(of: host(isAvailable: true, isSmartMode: true, state: .unsupported), as: .image(size: size))
    }
}
#endif
