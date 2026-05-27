import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Published state of the drag system, consumed by screen overlays
/// and row renderers to position the phantom and drop indicator.
public enum DragControllerState: Equatable, Sendable {
    case idle
    case dragging(DragSession)
    case dropping(DragSession, DragTarget)
}

/// `@MainActor` `ObservableObject` driving the custom drag-reorder
/// system. Lives in the platform-agnostic `DragReorder/` module.
///
/// State machine: `idle → dragging → dropping → idle`, with cancel
/// paths. Geometry, flatRows, and sortMode are inputs the screen
/// populates before each drop resolution is triggered (Task 5).
/// `onDrop` fires once on a successful release with a resolved target;
/// the owning container translates that into the appropriate store
/// call.
@MainActor
public final class DragController: ObservableObject {

    /// Current state of the drag gesture. Published so SwiftUI views
    /// receive automatic invalidation on each transition.
    @Published public private(set) var state: DragControllerState = .idle

    // MARK: - Inputs populated by the screen before drop resolution

    /// Flattened, ordered list of visible rows. Task 5 uses this for
    /// hit-testing and cycle detection.
    public var flatRows: [DragReorderRow] = []

    /// Rendered frame of each visible row, keyed by task ID.
    public var geometry: [UUID: CGRect] = [:]

    /// Active sort mode; governs which drop targets are valid.
    public var sortMode: DragSortMode = .personalized

    /// Whether a smart filter is active (affects reorder legality).
    public var isFilterActive: Bool = false

    // MARK: - Callback

    /// Called exactly once per successful drop (target is `.between`
    /// or `.onto`). Never called for `.rejected` or `.none`.
    public let onDrop: (_ draggedID: UUID, _ target: DragTarget) -> Void

    // MARK: - Init

    public init(onDrop: @escaping (UUID, DragTarget) -> Void) {
        self.onDrop = onDrop
    }

    // MARK: - State transitions

    /// Transition `idle → dragging`. Ignored if already dragging —
    /// prevents a second long-press from hijacking an in-flight drag.
    public func beginDrag(rowID: UUID, originalHeight: CGFloat, cursorY: CGFloat) {
        guard case .idle = state else { return }
        state = .dragging(DragSession(
            draggedID: rowID,
            originalHeight: originalHeight,
            cursorY: cursorY,
            target: .none
        ))
    }

    /// Update the cursor Y within the current `dragging` session.
    /// Ignored when not in the `.dragging` state.
    public func updateCursor(y: CGFloat) {
        guard case .dragging(var session) = state else { return }
        session.cursorY = y
        state = .dragging(session)
    }

    /// Store a resolved drop target (computed by Task 5's resolver) on
    /// the current session. Ignored when not dragging.
    public func setResolvedTarget(_ target: DragTarget) {
        guard case .dragging(var session) = state else { return }
        session.target = target
        state = .dragging(session)
    }

    /// Complete the drag: call `onDrop` if the target is actionable,
    /// then transition back to `.idle`.
    public func endDrag() {
        guard case .dragging(let session) = state else { return }
        let target = session.target
        state = .idle
        switch target {
        case .between, .onto:
            onDrop(session.draggedID, target)
        case .rejected, .none:
            break
        }
    }

    /// Abort the drag without firing `onDrop`. Returns to `.idle`.
    public func cancelDrag() {
        state = .idle
    }
}
