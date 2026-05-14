import Testing
import LillistCore
@testable import LillistUI

@Suite("StatusCycler")
struct StatusCyclerTests {
    @Test("Click cycles todo → started → closed → todo")
    func clickCycle() {
        #expect(StatusCycler.nextOnClick(from: .todo) == .started)
        #expect(StatusCycler.nextOnClick(from: .started) == .closed)
        #expect(StatusCycler.nextOnClick(from: .closed) == .todo)
    }

    @Test("Click on blocked goes back to todo (blocked never reached by click)")
    func clickFromBlocked() {
        #expect(StatusCycler.nextOnClick(from: .blocked) == .todo)
    }

    @Test("Space toggles started off and on")
    func spaceToggle() {
        #expect(StatusCycler.nextOnSpace(from: .todo) == .started)
        #expect(StatusCycler.nextOnSpace(from: .started) == .todo)
        #expect(StatusCycler.nextOnSpace(from: .blocked) == .started)
        #expect(StatusCycler.nextOnSpace(from: .closed) == .started)
    }
}
