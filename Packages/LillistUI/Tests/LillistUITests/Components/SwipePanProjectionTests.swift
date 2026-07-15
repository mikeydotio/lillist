import XCTest
import CoreGraphics
@testable import LillistUI

/// Pins the deceleration projection that converts a released pan's
/// translation + velocity into the predicted end translation fed to
/// `SwipeSettleArbiter`. The formula must match UIKit's standard
/// projection (`translation + velocity/1000 × rate/(1−rate)`) so the
/// bridged `HorizontalSwipePanGesture` reproduces the fling behavior
/// the SwiftUI `DragGesture.predictedEndTranslation` used to provide.
final class SwipePanProjectionTests: XCTestCase {

    func test_zeroVelocity_isIdentity() {
        XCTAssertEqual(
            SwipePanProjection.predictedTranslation(translation: -84, velocityPerSecond: 0),
            -84
        )
        XCTAssertEqual(
            SwipePanProjection.predictedTranslation(translation: 0, velocityPerSecond: 0),
            0
        )
    }

    func test_positiveVelocity_displacesPositively() {
        let predicted = SwipePanProjection.predictedTranslation(
            translation: 10, velocityPerSecond: 500
        )
        XCTAssertGreaterThan(predicted, 10)
    }

    func test_negativeVelocity_displacesNegatively() {
        let predicted = SwipePanProjection.predictedTranslation(
            translation: -10, velocityPerSecond: -500
        )
        XCTAssertLessThan(predicted, -10)
    }

    func test_monotonicInVelocity() {
        let velocities: [CGFloat] = [-2000, -300, 0, 300, 2000]
        let predictions = velocities.map {
            SwipePanProjection.predictedTranslation(translation: 25, velocityPerSecond: $0)
        }
        for (slower, faster) in zip(predictions, predictions.dropFirst()) {
            XCTAssertLessThan(slower, faster)
        }
    }

    func test_knownInput_matchesHandComputedValue() {
        // rate 0.998 → rate/(1−rate) = 499; 1000 pt/s → 1 pt/ms.
        // 100 + 1 × 499 = 599.
        let predicted = SwipePanProjection.predictedTranslation(
            translation: 100, velocityPerSecond: 1000
        )
        XCTAssertEqual(predicted, 599, accuracy: 0.0001)
    }

    func test_customDecelerationRate_matchesHandComputedValue() {
        // rate 0.5 → rate/(1−rate) = 1; 2000 pt/s → 2 pt/ms. 10 + 2 = 12.
        let predicted = SwipePanProjection.predictedTranslation(
            translation: 10, velocityPerSecond: 2000, decelerationRate: 0.5
        )
        XCTAssertEqual(predicted, 12, accuracy: 0.0001)
    }
}
