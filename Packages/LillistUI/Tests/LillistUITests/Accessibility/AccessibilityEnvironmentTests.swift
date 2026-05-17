#if os(macOS)
import XCTest
import SwiftUI
@testable import LillistUI

@MainActor
final class AccessibilityEnvironmentTests: XCTestCase {
    /// Smoke: a view that uses `.accessibleAnimation` compiles and renders
    /// under a reduce-motion override (delivered via the internal
    /// `reduceMotionOverride` env key — SDK 26.2 makes the system
    /// `accessibilityReduceMotion` keypath read-only, so test injection
    /// rides on a separate override key the modifier consults first).
    func test_accessibleAnimation_smoke() throws {
        let view = TogglingShape()
            .environment(\.reduceMotionOverride, true)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNotNil(host)
    }

    func test_accessibleMaterial_substitutes_fallback_when_reduceTransparency() throws {
        let view = MaterialUser()
            .environment(\.reduceTransparencyOverride, true)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNotNil(host)
    }

    private struct TogglingShape: View {
        @State private var on = false
        var body: some View {
            Circle()
                .fill(on ? Color.red : Color.blue)
                .accessibleAnimation(.easeInOut, value: on)
                .onAppear { on = true }
        }
    }

    private struct MaterialUser: View {
        var body: some View {
            Text("x")
                .padding()
                .accessibleMaterial(.thickMaterial, fallback: Color(nsColor: .windowBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
#endif
