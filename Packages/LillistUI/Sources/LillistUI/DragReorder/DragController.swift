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

    // MARK: - Resolution

    /// Compute the drop target for a cursor y-position. Pure function of
    /// the controller's `flatRows`, `geometry`, `sortMode`,
    /// `isFilterActive`, and the dragged row id.
    public func resolveTarget(forDraggedID draggedID: UUID, atY y: CGFloat) -> DragTarget {
        if isFilterActive { return .none }
        guard !flatRows.isEmpty else { return .none }

        // 1. Find the row whose frame contains y.
        if let hit = flatRows.first(where: { row in
            guard let frame = geometry[row.id] else { return false }
            return y >= frame.minY && y < frame.maxY
        }) {
            let frame = geometry[hit.id]!
            let zone = classifyZone(y: y, in: frame)
            return resolve(zone: zone, hit: hit, draggedID: draggedID)
        }

        // 2. Below the last row — treat as drop at root end.
        if let last = flatRows.last,
           let lastFrame = geometry[last.id],
           y >= lastFrame.maxY,
           sortMode == .personalized {
            return finalize(
                target: .between(beforeID: nil, afterID: last.id, parentID: nil),
                draggedID: draggedID
            )
        }

        return .none
    }

    private enum Zone { case top25, middle50, bottom25 }

    private func classifyZone(y: CGFloat, in frame: CGRect) -> Zone {
        let topBand    = frame.minY + frame.height * 0.25
        let bottomBand = frame.minY + frame.height * 0.75
        if y < topBand    { return .top25 }
        if y >= bottomBand { return .bottom25 }
        return .middle50
    }

    private func resolve(zone: Zone, hit: DragReorderRow, draggedID: UUID) -> DragTarget {
        switch zone {
        case .middle50:
            return finalize(target: .onto(targetID: hit.id), draggedID: draggedID)
        case .top25:
            guard sortMode == .personalized else { return .none }
            return finalize(target: resolveBetweenAbove(hit), draggedID: draggedID)
        case .bottom25:
            guard sortMode == .personalized else { return .none }
            return finalize(target: resolveBetweenBelow(hit), draggedID: draggedID)
        }
    }

    /// Dragged row will sit BEFORE `hit` (drop in hit's top 25%).
    /// beforeID = hit; afterID = previous flat row that's a sibling of hit (same parent), if any.
    private func resolveBetweenAbove(_ hit: DragReorderRow) -> DragTarget {
        let parent = hit.parentID
        let previous = flatRows
            .prefix(while: { $0.id != hit.id })
            .reversed()
            .first(where: { $0.parentID == parent })
        return .between(beforeID: hit.id, afterID: previous?.id, parentID: parent)
    }

    /// Dragged row will sit AFTER `hit` (drop in hit's bottom 25%).
    /// Three sub-cases based on the next flat row:
    /// - next has hit as parent (hit is expanded, next is first child):
    ///     dragged becomes first child of hit. beforeID = next, afterID = nil, parent = hit.
    /// - next has same parent as hit: between them at hit's depth.
    /// - depth decreases (or no next): sibling-after hit, last in its sibling group.
    private func resolveBetweenBelow(_ hit: DragReorderRow) -> DragTarget {
        guard let hitIndex = flatRows.firstIndex(where: { $0.id == hit.id }) else {
            return .none
        }
        let nextIndex = hitIndex + 1
        if nextIndex >= flatRows.count {
            return .between(beforeID: nil, afterID: hit.id, parentID: hit.parentID)
        }
        let next = flatRows[nextIndex]
        if next.parentID == hit.id {
            return .between(beforeID: next.id, afterID: nil, parentID: hit.id)
        } else if next.parentID == hit.parentID {
            return .between(beforeID: next.id, afterID: hit.id, parentID: hit.parentID)
        } else {
            return .between(beforeID: nil, afterID: hit.id, parentID: hit.parentID)
        }
    }

    /// Apply cycle-rejection on top of a resolved target.
    private func finalize(target: DragTarget, draggedID: UUID) -> DragTarget {
        switch target {
        case .onto(let id) where isSelfOrDescendant(id, of: draggedID):
            return .rejected
        case .between(_, _, let parentID?) where isSelfOrDescendant(parentID, of: draggedID):
            return .rejected
        default:
            return target
        }
    }

    /// Walk the parent chain from `candidate` upward. Returns `true` if
    /// `candidate` is `ancestor` itself or any descendant of it.
    private func isSelfOrDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
        if candidate == ancestor { return true }
        var cursor: UUID? = candidate
        var safety = 0
        while let c = cursor, safety < 1024 {
            if c == ancestor { return true }
            cursor = flatRows.first(where: { $0.id == c })?.parentID
            safety += 1
        }
        return false
    }
}
