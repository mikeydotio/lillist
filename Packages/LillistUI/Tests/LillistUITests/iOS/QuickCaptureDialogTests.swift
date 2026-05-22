#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import LillistUI

/// Structural smoke tests for `QuickCaptureDialog`. The visual contract
/// is enforced by `iOSSnapshotTests`; this file only confirms the view
/// constructs across the states a host actually drives.
///
/// The parser itself is exercised by `QuickCaptureParserTests`. The
/// empty-title guard lives in the iOS app target's
/// `QuickCaptureDialogGuardTests`.
final class QuickCaptureDialogTests: XCTestCase {
    @MainActor
    func test_constructs_with_empty_text() {
        let view = QuickCaptureDialog(
            text: .constant(""),
            onSubmit: {}
        )
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 200)
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(host.view.bounds.width, 0)
    }

    @MainActor
    func test_constructs_with_parsed_tokens() {
        let view = QuickCaptureDialog(
            text: .constant("Buy milk #errands ^tomorrow"),
            onSubmit: {}
        )
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 220)
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(host.view.bounds.height, 0)
    }

    @MainActor
    func test_constructs_with_error_message() {
        let view = QuickCaptureDialog(
            text: .constant("Anything"),
            errorMessage: "Couldn't create task",
            onSubmit: {}
        )
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 240)
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(host.view.bounds.height, 0)
    }
}
#endif
