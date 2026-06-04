import Testing
@testable import LillistCore

@Suite("FractionalPosition")
struct FractionalPositionTests {
    @Test("Insert into empty list yields 1.0")
    func empty() {
        let p = FractionalPosition.position(after: nil, before: nil)
        #expect(p == 1.0)
    }

    @Test("Insert at end yields after+1")
    func atEnd() {
        let p = FractionalPosition.position(after: 5.0, before: nil)
        #expect(p == 6.0)
    }

    @Test("Insert at start yields before-1")
    func atStart() {
        let p = FractionalPosition.position(after: nil, before: 3.0)
        #expect(p == 2.0)
    }

    @Test("Insert between two yields midpoint")
    func between() {
        let p = FractionalPosition.position(after: 2.0, before: 4.0)
        #expect(p == 3.0)
    }

    @Test("Adjacent neighbors yield midpoint")
    func adjacent() {
        let p = FractionalPosition.position(after: 2.0, before: 3.0)
        #expect(p == 2.5)
    }

    @Test("Very close neighbors still produce a strictly-between value")
    func tinyGap() {
        let after = 1.0
        let before = 1.0 + .ulpOfOne * 10
        let p = FractionalPosition.position(after: after, before: before)
        #expect(p > after)
        #expect(p < before)
    }

    @Test("Detects gap too small for further subdivision")
    func gapTooSmall() {
        let after = 1.0
        let before = after.nextUp
        #expect(FractionalPosition.gapIsTooSmall(after: after, before: before) == true)
    }

    @Test("Normal gap is not flagged as too small")
    func normalGap() {
        #expect(FractionalPosition.gapIsTooSmall(after: 1.0, before: 2.0) == false)
    }

    @Test("anchorsAreOutOfOrder is true only when after >= before")
    func anchorOrdering() {
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 3.0, before: 2.0) == true)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 2.0, before: 2.0) == true)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 2.0, before: 3.0) == false)
    }

    @Test("anchorsAreOutOfOrder is false when either anchor is nil")
    func anchorOrderingWithNil() {
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: nil, before: 2.0) == false)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 2.0, before: nil) == false)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: nil, before: nil) == false)
    }

    @Test("needsCompaction fires only when both real neighbors are too close")
    func needsCompactionTwoNeighbors() {
        let after = 1.0
        #expect(FractionalPosition.needsCompaction(after: after, before: after.nextUp) == true)
        #expect(FractionalPosition.needsCompaction(after: 1.0, before: 2.0) == false)
    }

    @Test("needsCompaction is false at the head or tail (nil neighbor)")
    func needsCompactionEdges() {
        #expect(FractionalPosition.needsCompaction(after: nil, before: 1.0) == false)
        #expect(FractionalPosition.needsCompaction(after: 1.0, before: nil) == false)
        #expect(FractionalPosition.needsCompaction(after: nil, before: nil) == false)
    }
}
