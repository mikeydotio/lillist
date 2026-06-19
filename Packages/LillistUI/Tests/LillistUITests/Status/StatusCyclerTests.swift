import Testing
import LillistCore
@testable import LillistUI

@Suite("StatusCycler")
struct StatusCyclerTests {
    @Test("Click advances todo → started → closed, with closed terminal")
    func clickCycle() {
        #expect(StatusCycler.nextOnClick(from: .todo) == .started)
        #expect(StatusCycler.nextOnClick(from: .started) == .closed)
        // Closed is terminal — a further tap does not loop back past "done".
        #expect(StatusCycler.nextOnClick(from: .closed) == .closed)
    }

    @Test("Click on blocked advances to started (unblock & resume)")
    func clickFromBlocked() {
        #expect(StatusCycler.nextOnClick(from: .blocked) == .started)
    }
}
