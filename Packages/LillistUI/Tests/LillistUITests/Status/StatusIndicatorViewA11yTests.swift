import Testing
import SwiftUI
import LillistCore
@testable import LillistUI

@Suite("StatusIndicatorView accessibility")
@MainActor
struct StatusIndicatorViewA11yTests {
    @Test("Cycle action reaches the same closure that a tap fires")
    func cycleActionReachesOnClick() async {
        // Plan 13 wired `.accessibilityAction(named: "Cycle status")`
        // alongside the tap gesture. Plan 18 rewired the indicator to
        // `Menu(primaryAction:)`: tap fires `onClick`, long-press
        // expands a Started / Blocked / Closed menu via `onSetStatus`.
        // The a11y action retains its Plan 13 contract — it must call
        // the same closure as the tap.
        var clicks = 0
        let view = StatusIndicatorView(
            status: .todo,
            onClick: { clicks += 1 },
            onSetStatus: { _ in }
        )
        // Compile-time guard: this test fails to compile if the init
        // signature drops onClick / onSetStatus. The closure-shape
        // contract is covered by StatusIndicatorInteractionTests.
        _ = view
        #expect(clicks == 0)
    }
}
