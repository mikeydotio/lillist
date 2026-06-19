import CoreGraphics

/// Pure axis decision shared by the macOS reorder gesture's arbitration with
/// the horizontal swipe (`SwipeableRow`).
///
/// macOS has no long-press gate, so the reorder `DragGesture` and the swipe
/// both observe a bare drag from the first pixel. To keep them mutually
/// exclusive each commits to an axis on first real movement: only a
/// `.vertical` commit drives a reorder; a `.horizontal` commit is yielded to
/// the swipe. Extracted from the gesture so the contract is unit-testable.
enum DragAxisArbiter {
    enum Axis { case vertical, horizontal }

    /// The committed axis for a drag translation, or `nil` while the drag has
    /// not yet travelled `commitDistance` (still undecided).
    ///
    /// Ties resolve to `.vertical`: reorder is the row's primary vertical
    /// gesture, so an ambiguous (diagonal) drag favours it over the swipe.
    static func axis(forTranslation translation: CGSize, commitDistance: CGFloat) -> Axis? {
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        guard max(dx, dy) >= commitDistance else { return nil }
        return dy >= dx ? .vertical : .horizontal
    }
}
