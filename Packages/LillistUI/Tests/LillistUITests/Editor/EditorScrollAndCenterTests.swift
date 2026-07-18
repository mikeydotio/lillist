import Testing
import SwiftUI
@testable import LillistUI

/// Pins the editor's outer-scroll environment contract (issue #38).
@Suite("EditorScrollAndCenter environment")
struct EditorScrollAndCenterTests {
    /// Fail-safe: the flag must default to `false`, so a host that never applies
    /// `editorScrollAndCenter` (the macOS hotkey `NSPanel`) keeps its child popups
    /// on the self-bounding, never-clips branch. Only the overlay opts into hug.
    @Test("editorHasOuterScroll defaults to false (children self-bound when unhosted)")
    func defaultsFalse() {
        #expect(EnvironmentValues().editorHasOuterScroll == false)
    }

    #if canImport(UIKit)
    /// The host contract that keeps the scroll-less `NSPanel` from clipping:
    /// without an outer scroll a child body self-bounds to `editorChildMaxHeight`
    /// and scrolls internally; with one it hugs its (taller) content so the single
    /// overlay scroll handles overflow. Guards against a future host silently
    /// clipping a long attachments/journal list.
    @Test("EditorChildBody bounds without an outer scroll, hugs with one")
    @MainActor func boundsWithoutOuterScroll_hugsWithOne() {
        // Content taller than the child cap so the two branches diverge.
        let tall = VStack(spacing: 0) {
            ForEach(0..<40, id: \.self) { i in
                Text("row \(i)").frame(height: 30)
            }
        }
        func height(outerScroll: Bool) -> CGFloat {
            let root = EditorChildBody { tall }
                .environment(\.editorHasOuterScroll, outerScroll)
            let host = UIHostingController(rootView: AnyView(root))
            return host.sizeThatFits(in: CGSize(width: 360, height: 100_000)).height
        }
        let bounded = height(outerScroll: false)
        let hugged = height(outerScroll: true)

        #expect(hugged > bounded)
        #expect(bounded <= LillistSizing.editorChildMaxHeight + 1)
        #expect(hugged > LillistSizing.editorChildMaxHeight)
    }
    #endif
}
