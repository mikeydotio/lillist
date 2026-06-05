import Testing
@testable import LillistUI

@Suite("ReorderActionDispatch")
struct ReorderActionDispatchTests {
    @Test("Only actions with a non-nil closure are available")
    func availableActionsExcludeNilClosures() {
        let dispatch = ReorderActionDispatch(
            onMoveUp: {},
            onMoveDown: nil,
            onIndent: {},
            onOutdent: nil
        )
        #expect(dispatch.availableActions == [.moveUp, .indent])
    }

    @Test("Empty when all closures are nil")
    func availableActionsEmptyWhenAllNil() {
        let dispatch = ReorderActionDispatch(
            onMoveUp: nil,
            onMoveDown: nil,
            onIndent: nil,
            onOutdent: nil
        )
        #expect(dispatch.availableActions.isEmpty)
    }

    @Test("Invoking an available action fires exactly its closure")
    func invokeFiresExactClosure() {
        var calls: [ReorderAction] = []
        let dispatch = ReorderActionDispatch(
            onMoveUp: { calls.append(.moveUp) },
            onMoveDown: { calls.append(.moveDown) },
            onIndent: { calls.append(.indent) },
            onOutdent: { calls.append(.outdent) }
        )
        dispatch.invoke(.moveUp)
        dispatch.invoke(.outdent)
        #expect(calls == [.moveUp, .outdent])
    }

    @Test("Invoking an unavailable (nil-closure) action is a no-op")
    func invokeNilClosureIsNoOp() {
        var fired = false
        let dispatch = ReorderActionDispatch(
            onMoveUp: { fired = true },
            onMoveDown: nil,
            onIndent: nil,
            onOutdent: nil
        )
        dispatch.invoke(.moveDown) // no closure registered
        dispatch.invoke(.indent)   // no closure registered
        #expect(fired == false)
    }

    @Test("Every action carries a stable accessibility key")
    func actionKeysAreStable() {
        #expect(ReorderAction.moveUp.accessibilityKey == "Move up")
        #expect(ReorderAction.moveDown.accessibilityKey == "Move down")
        #expect(ReorderAction.indent.accessibilityKey == "Indent")
        #expect(ReorderAction.outdent.accessibilityKey == "Outdent")
    }
}
