import Testing
@testable import LillistCore

@Suite("PositionCompactor")
struct PositionCompactorTests {
    @Test("Empty array yields empty result")
    func empty() {
        let result = PositionCompactor.recompact(positions: [])
        #expect(result == [])
    }

    @Test("Already-spaced positions stay relatively ordered")
    func preservesOrder() {
        let result = PositionCompactor.recompact(positions: [1.0, 2.0, 3.0])
        #expect(result.count == 3)
        #expect(result[0] < result[1])
        #expect(result[1] < result[2])
    }

    @Test("Squashed neighbors get re-spaced")
    func respacingSquashed() {
        let squashed = [1.0, 1.0 + .ulpOfOne, 1.0 + .ulpOfOne * 2]
        let result = PositionCompactor.recompact(positions: squashed)
        for i in 1..<result.count {
            #expect(result[i] - result[i - 1] >= 1.0)
        }
    }

    @Test("Preserves the order of the input")
    func orderInvariant() {
        let input = [5.0, 2.0, 3.0, 1.0, 4.0]
        let result = PositionCompactor.recompact(positions: input)
        #expect(result.count == input.count)
    }
}
