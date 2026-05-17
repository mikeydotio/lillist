import AppKit

/// Pure-math placement helper for the Quick Capture panel. Lives in
/// its own file so the standalone test bundle can co-compile just this
/// (without dragging in `QuickCapturePanelController`'s `AppEnvironment`
/// and SwiftUI dependencies).
enum QuickCapturePlacementMath {
    /// Given a screen frame, that screen's visible frame (excluding
    /// the menu bar and Dock), and the panel's size, return the
    /// bottom-left origin that centers the panel horizontally and
    /// places its top edge ~1/3 down from the top of the visible frame.
    ///
    /// AppKit uses bottom-left-origin coordinates, so the panel's
    /// `origin.y` equals
    /// `visibleFrame.maxY - (visibleFrame.height / 3) - panelSize.height`.
    static func placementOrigin(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        panelSize: NSSize
    ) -> NSPoint {
        let x = screenFrame.origin.x + (screenFrame.width - panelSize.width) / 2
        let y = visibleFrame.maxY - (visibleFrame.height / 3) - panelSize.height
        return NSPoint(x: x, y: y)
    }
}
