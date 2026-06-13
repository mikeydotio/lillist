#if os(macOS)
import SwiftUI
import AppKit
import SnapshotTesting
@testable import LillistUI

/// Wraps a view with deterministic environment for snapshotting.
/// Fixtures sit on `LillistColor.workspace` — the app's actual surface —
/// so dark-scheme baselines exercise real contrast instead of rendering
/// near-white text onto the bitmap's default white canvas (which made
/// pre-Rainbow dark baselines unreadable and verified nothing).
struct SnapshotHost<Content: View>: View {
    let colorScheme: ColorScheme
    let content: () -> Content
    var body: some View {
        content()
            .frame(minWidth: 320, minHeight: 240)
            .background(LillistColor.workspace)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, Locale(identifier: "en_US"))
    }
}

/// Render a SwiftUI view into an `NSView` at a fixed size for snapshotting.
/// swift-snapshot-testing 1.17 only provides macOS image strategies for
/// `NSView` and `NSViewController`, not for SwiftUI `View` directly — so we
/// host into an `NSHostingView` here.
@MainActor
func makeHostingView<V: View>(_ view: V, size: CGSize) -> NSView {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    return host
}
#endif
