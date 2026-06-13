import XCTest
@testable import LillistUI
import LillistCore

/// Full transition × Reduce-Motion matrix for the completion burst.
final class ConfettiPolicyTests: XCTestCase {

    func testBurstsOnlyOnTransitionsIntoClosed() {
        for old in Status.allCases {
            for new in Status.allCases {
                let expected = (old != .closed && new == .closed)
                XCTAssertEqual(
                    ConfettiPolicy.shouldBurst(from: old, to: new, reduceMotion: false),
                    expected,
                    "\(old) → \(new)"
                )
            }
        }
    }

    func testReduceMotionSuppressesEveryBurst() {
        for old in Status.allCases {
            for new in Status.allCases {
                XCTAssertFalse(
                    ConfettiPolicy.shouldBurst(from: old, to: new, reduceMotion: true),
                    "\(old) → \(new) must stay quiet under Reduce Motion"
                )
            }
        }
    }

    func testReclosingAClosedTaskStaysQuiet() {
        XCTAssertFalse(ConfettiPolicy.shouldBurst(from: .closed, to: .closed, reduceMotion: false))
    }
}
