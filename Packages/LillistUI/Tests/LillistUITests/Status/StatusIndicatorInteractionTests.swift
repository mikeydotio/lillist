import Testing
import SwiftUI
@testable import LillistUI
import LillistCore

/// Plan 18 Task 1: StatusIndicatorView's primary action fires `onClick`
/// (existing cycle contract from Plan 13) and its menu surfaces three
/// explicit status setters via `onSetStatus`. This suite pins the
/// closure-forwarding contract; visual / gesture behaviour is covered
/// by the iOS snapshot tests.
@Suite("StatusIndicatorView closure contract")
@MainActor
struct StatusIndicatorInteractionTests {
    @Test("onSetStatus forwards the chosen Status verbatim")
    func setStatusForwardsArgument() {
        var received: [Status] = []
        let view = StatusIndicatorView(
            status: .todo,
            onClick: {},
            onSetStatus: { received.append($0) }
        )
        view.onSetStatus(.started)
        view.onSetStatus(.blocked)
        view.onSetStatus(.closed)
        #expect(received == [.started, .blocked, .closed])
    }

    @Test("onClick remains a no-arg closure separate from onSetStatus")
    func onClickIsIndependentOfOnSetStatus() {
        var clicks = 0
        var setStatusCalls: [Status] = []
        let view = StatusIndicatorView(
            status: .started,
            onClick: { clicks += 1 },
            onSetStatus: { setStatusCalls.append($0) }
        )
        view.onClick()
        view.onClick()
        #expect(clicks == 2)
        #expect(setStatusCalls.isEmpty)
    }
}
