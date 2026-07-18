import Testing
import SwiftUI
import LillistUI

/// Pins the fail-safe contract of the editor's outer-scroll environment flag:
/// it must default to `false`, so a host that never applies
/// `editorScrollAndCenter` (e.g. the macOS hotkey `NSPanel`) keeps its child
/// popups on the self-bounding, never-clips branch. Only the overlay's
/// `editorScrollAndCenter` opts into the hugging branch.
@Suite("EditorScrollAndCenter environment")
struct EditorScrollAndCenterTests {
    @Test("editorHasOuterScroll defaults to false (children self-bound when unhosted)")
    func defaultsFalse() {
        #expect(EnvironmentValues().editorHasOuterScroll == false)
    }
}
