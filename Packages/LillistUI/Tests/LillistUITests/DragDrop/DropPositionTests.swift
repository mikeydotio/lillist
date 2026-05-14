import Testing
import CoreGraphics
@testable import LillistUI

@Suite("DropPosition")
struct DropPositionTests {
    @Test("Top 25% of row → .before")
    func before() {
        let p = DropPosition.classify(yInRow: 5, rowHeight: 40)
        #expect(p == .before)
    }

    @Test("Middle 50% of row → .onto")
    func onto() {
        let p = DropPosition.classify(yInRow: 20, rowHeight: 40)
        #expect(p == .onto)
    }

    @Test("Bottom 25% of row → .after")
    func after() {
        let p = DropPosition.classify(yInRow: 35, rowHeight: 40)
        #expect(p == .after)
    }
}
