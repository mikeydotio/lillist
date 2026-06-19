import Combine
import CoreGraphics
import Foundation
import LillistCore
import SwiftUI

/// Published state of the drag system, consumed by screen overlays
/// and row renderers to position the phantom and drop indicator.
public enum DragControllerState: Equatable, Sendable {
    case idle
    case dragging(DragSession)
    /// Reserved for a future drop-animation phase: phantom animates to its
    /// destination while the gap closes. Not currently emitted —
    /// `endDrag()` transitions directly from `.dragging` to `.idle`.
    /// See `docs/plans/2026-05-26-drag-reorder-redesign-design.md` §"Animation and gap behavior".
    case dropping(DragSession, DragTarget)
}

/// `@MainActor` `ObservableObject` driving the custom drag-reorder
/// system. Lives in the platform-agnostic `DragReorder/` module.
///
/// State machine: `idle → dragging → idle`. A `.dropping` transition is
/// reserved for the future animated-drop phase (see design doc).
/// Geometry, flatRows, and sortMode are inputs the screen populates
/// before each drop resolution is triggered (Task 5). The configured
/// drop handler is invoked once on a successful release with a resolved
/// target; the owning container translates that into the appropriate
/// store call.
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

    /// Optional diagnostic sink. When non-nil, the drag lifecycle emits
    /// `drag.start` / `drag.over` / `drag.drop` events. Emission is non-blocking
    /// (`Task { await … }`) so it never stalls a gesture; `DiagnosticLog` stamps
    /// the authoritative process + seq. Wired by the screen in `.onAppear`.
    public var diagnosticLog: DiagnosticSink?

    // MARK: - Callback

    /// Internal drop handler. Called exactly once per successful drop
    /// (target is `.between`). Never called for `.rejected`
    /// or `.none`. Late-bound via `setOnDrop(_:)` so SwiftUI containers
    /// that can't capture `self` in `@StateObject` init can wire the
    /// real closure from `.onAppear`.
    private var handler: (UUID, DragTarget) -> Void

    // MARK: - Init

    /// Create a controller with an optional immediate drop handler.
    /// Pass no argument (or `{ _, _ in }`) when the real handler will
    /// be supplied via `setOnDrop(_:)` from `.onAppear`.
    public init(onDrop: @escaping (UUID, DragTarget) -> Void = { _, _ in }) {
        self.handler = onDrop
    }

    /// Replace the drop handler. Used by SwiftUI containers that can't
    /// capture `self` in the `@StateObject` default value at struct-init
    /// time; they wire the real handler from `.onAppear`.
    public func setOnDrop(_ closure: @escaping (UUID, DragTarget) -> Void) {
        self.handler = closure
    }

    // MARK: - State transitions

    /// Transition `idle → dragging`. Ignored if already dragging —
    /// prevents a second long-press from hijacking an in-flight drag.
    /// `cursorY` is captured as both the **anchor** (`initialCursorY`)
    /// and the current cursor position. The anchor is fixed for the
    /// lifetime of the drag and is what `updateCursor(translation:)`
    /// adds to and what the overlay falls back to as the settle target
    /// when a drop is rejected.
    public func beginDrag(rowID: UUID, originalHeight: CGFloat, cursorY: CGFloat) {
        guard case .idle = state else { return }
        state = .dragging(DragSession(
            draggedID: rowID,
            originalHeight: originalHeight,
            initialCursorY: cursorY,
            cursorY: cursorY,
            target: .none
        ))
        let sourceIndex = flatRows.firstIndex(where: { $0.id == rowID })
        emit("drag.start", [
            "draggedID": .string(rowID.uuidString),
            "sourceIndex": sourceIndex.map { .int($0) } ?? .null,
        ])
    }

    /// Update the cursor Y absolutely within the current `dragging`
    /// session. Used by synthetic-geometry tests and snapshot fixtures.
    /// Ignored when not in the `.dragging` state.
    public func updateCursor(y: CGFloat) {
        guard case .dragging(var session) = state else { return }
        session.cursorY = y
        state = .dragging(session)
    }

    /// Update the cursor by gesture *translation* — i.e. the delta
    /// since drag begin. This is the preferred update channel from a
    /// live `DragGesture` because translation is coordinate-space-
    /// invariant: it remains correct even when `drag.location` is
    /// reported in an unexpected coordinate space (as it sometimes is
    /// at the first event of `LongPressGesture.sequenced(before:)`).
    public func updateCursor(translation: CGFloat) {
        guard case .dragging(var session) = state else { return }
        session.cursorY = session.initialCursorY + translation
        state = .dragging(session)
    }

    /// Store a resolved drop target (computed by Task 5's resolver) on
    /// the current session. Ignored when not dragging.
    public func setResolvedTarget(_ target: DragTarget) {
        guard case .dragging(var session) = state else { return }
        session.target = target
        state = .dragging(session)
        // Emitted 1:1 with each call. The modifier coalesces unchanged targets
        // (`DragReorderable`'s `if resolved != previous` guard), so in practice
        // this only fires when the highlighted target actually changes.
        emit("drag.over", Self.targetPayload(target))
    }

    /// Complete the drag.
    ///
    /// 1. Invoke the drop handler immediately if the target is
    ///    actionable (`.between`) — data updates are never
    ///    delayed by the settle animation.
    /// 2. If `settleDuration > 0`, transition `.dragging → .dropping`
    ///    so the overlay can animate the phantom from its lifted
    ///    state at `cursorY` back to natural scale/opacity at the
    ///    resolved drop position; then asynchronously transition to
    ///    `.idle` after the window elapses.
    /// 3. If `settleDuration == 0` (default), transition straight to
    ///    `.idle`. This preserves the prior behavior for tests that
    ///    don't care about the animated phase.
    public func endDrag(settleDuration: TimeInterval = 0) {
        guard case .dragging(let session) = state else { return }
        let target = session.target

        // Emit BEFORE dispatch so rejected/none releases (which never call the
        // handler) are still recorded — a cancelled drop is diagnostically useful.
        var dropPayload = Self.targetPayload(target)
        dropPayload["draggedID"] = .string(session.draggedID.uuidString)
        emit("drag.drop", dropPayload)

        switch target {
        case .between:
            handler(session.draggedID, target)
        case .rejected, .none:
            break
        }

        guard settleDuration > 0 else {
            state = .idle
            return
        }

        state = .dropping(session, target)
        let draggedID = session.draggedID
        let nanos = UInt64(settleDuration * 1_000_000_000)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self else { return }
            if case .dropping(let s, _) = self.state, s.draggedID == draggedID {
                self.state = .idle
            }
        }
    }

    /// Abort the drag without firing `onDrop`. Returns to `.idle`.
    public func cancelDrag() {
        state = .idle
    }

    /// The cell the dragged row will nest under if dropped now — the resolved
    /// `.between` target's `parentID` while actively dragging. `nil` for
    /// top-level drops, and while settling or idle. Screens read this to give
    /// the future-parent row a gentle highlight; it updates reactively as the
    /// resolved depth changes mid-drag.
    public var dropTargetParentID: UUID? {
        guard case .dragging(let session) = state,
              case .between(_, _, let parentID) = session.target
        else { return nil }
        return parentID
    }

    // MARK: - Resolution

    /// Compute the drop target for a cursor position. Pure function of the
    /// controller's `flatRows`, `geometry`, `sortMode`, `isFilterActive`, the
    /// dragged row id, and the gesture's vertical/horizontal translation.
    ///
    /// Vertical position selects the **gap** between two visible rows; horizontal
    /// translation selects the **depth** within that gap's valid range
    /// (Reminders-style indent/outdent). With no horizontal movement the row
    /// keeps its current nesting depth (clamped to what the gap allows); pulling
    /// left outdents (toward top level), pulling right nests deeper. The dragged
    /// row's own subtree is excluded from the reference list so it can never
    /// become its own neighbor or parent.
    public func resolveTarget(
        forDraggedID draggedID: UUID,
        atY y: CGFloat,
        horizontalTranslation: CGFloat = 0
    ) -> DragTarget {
        if isFilterActive { return .none }
        // Reordering is only meaningful in the personalized (manual) sort.
        guard sortMode == .personalized else { return .none }

        let refs = referenceRows(excludingSubtreeOf: draggedID)
        guard !refs.isEmpty else { return .none }

        let (above, below) = gapNeighbors(atY: y, in: refs)

        // Valid depth range for this gap. In a DFS-flattened list this is always
        // non-empty: `below.depth <= above.depth + 1`.
        let minDepth = below?.depth ?? 0
        let maxDepth = above.map { $0.depth + 1 } ?? 0

        // Baseline = the dragged row's current depth (→ "keep current nesting").
        // Each ~half-indent of horizontal travel shifts one level; `rounded()`
        // gives the half-indent dead-zone for free so incidental wobble is inert.
        let baseline = flatRows.first(where: { $0.id == draggedID })?.depth ?? 0
        let shift = Int((horizontalTranslation / LillistDragTokens.indentPerLevel).rounded())
        let depth = min(max(baseline + shift, minDepth), maxDepth)

        // Derive parent + sibling anchors from the gap and chosen depth.
        let parentID = depth == 0
            ? nil
            : above.flatMap { ancestorOrSelf(of: $0, atDepth: depth - 1, in: refs)?.id }
        let afterID = above.flatMap { ancestorOrSelf(of: $0, atDepth: depth, in: refs)?.id }
        let beforeID = (below?.depth == depth) ? below?.id : nil

        return finalize(
            target: .between(beforeID: beforeID, afterID: afterID, parentID: parentID),
            draggedID: draggedID
        )
    }

    /// Vertical position for the drop indicator: the insertion fencepost
    /// nearest the drag touch, computed over the **reference rows** — the
    /// current visual list minus the dragged row and its descendants (the same
    /// set the resolver's `gapNeighbors` uses).
    ///
    /// Excluding the dragged subtree collapses its slot into the surrounding
    /// gap, so there is exactly **one** fencepost per reference gap — the line
    /// and the resolver share a single gap model. Without this, the dragged
    /// row's own slot splits into two equivalent fenceposts (just-above and
    /// just-below the source) that resolve to the same drop, showing a bogus
    /// second destination.
    ///
    /// Still anchored to *current* positions (not the post-sort layout), so for
    /// a de-parenting drag the line stays where the finger points rather than
    /// jumping to where the row will land after the list re-sorts. Each
    /// reference row owns the half-gap above and below its midline; a cursor in
    /// the collapsed gap resolves to that gap's midpoint (≈ the dragged row's
    /// current centre). Returns `nil` when no reference geometry is known.
    public func insertionIndicatorY(forCursorY cursorY: CGFloat, draggedID: UUID) -> CGFloat? {
        let refIDs = Set(referenceRows(excludingSubtreeOf: draggedID).map(\.id))
        let placed = flatRows
            .filter { refIDs.contains($0.id) }
            .compactMap { geometry[$0.id] }
            .sorted { $0.minY < $1.minY }
        guard !placed.isEmpty else { return nil }
        var previousMaxY: CGFloat?
        for frame in placed {
            if cursorY < frame.midY {
                if let previousMaxY { return (previousMaxY + frame.minY) / 2 }
                return frame.minY
            }
            previousMaxY = frame.maxY
        }
        return previousMaxY
    }

    /// The visible rows that can serve as drop neighbors — `flatRows` minus the
    /// dragged row and its descendants. Descendants stay *visible* during a drag
    /// (only the dragged row itself is hidden), so they're excluded by walking
    /// parent links, not by visibility. Relies on `flatRows` being in DFS order:
    /// a descendant always follows its ancestor, so one forward pass propagates
    /// the excluded set.
    private func referenceRows(excludingSubtreeOf draggedID: UUID) -> [DragReorderRow] {
        var excluded: Set<UUID> = [draggedID]
        for row in flatRows {
            if let pid = row.parentID, excluded.contains(pid) {
                excluded.insert(row.id)
            }
        }
        return flatRows.filter { !excluded.contains($0.id) }
    }

    /// Locate the gap `y` falls into, as its bracketing reference rows. Each row
    /// is split 50/50 at its vertical midline: `y` above a row's midline puts the
    /// gap *above* that row (it becomes `below`); below the midline puts the gap
    /// *below* it (it becomes `above`). Returns `(nil, first)` at the list start
    /// and `(last, nil)` at the end. The dragged row's hidden slot is just empty
    /// space between reference rows, so a cursor there resolves to the
    /// surrounding gap.
    private func gapNeighbors(
        atY y: CGFloat,
        in refs: [DragReorderRow]
    ) -> (above: DragReorderRow?, below: DragReorderRow?) {
        var above: DragReorderRow?
        for row in refs {
            guard let frame = geometry[row.id] else { continue }
            if y < frame.midY {
                return (above, row)
            }
            above = row
        }
        return (above, nil)
    }

    /// Walk `row`'s ancestor chain (within `refs`) to the row at exactly
    /// `depth`. Returns `row` itself when `row.depth == depth`, and `nil` when
    /// `depth` is deeper than `row` (no such ancestor) or negative.
    private func ancestorOrSelf(
        of row: DragReorderRow,
        atDepth depth: Int,
        in refs: [DragReorderRow]
    ) -> DragReorderRow? {
        guard depth >= 0, depth <= row.depth else { return nil }
        var current: DragReorderRow? = row
        while let c = current {
            if c.depth == depth { return c }
            current = c.parentID.flatMap { pid in refs.first(where: { $0.id == pid }) }
        }
        return nil
    }

    /// Apply cycle-rejection on top of a resolved target. With the dragged
    /// subtree excluded from the reference list the resolved parent can never be
    /// inside that subtree, so this is defense-in-depth (the store re-checks).
    private func finalize(target: DragTarget, draggedID: UUID) -> DragTarget {
        switch target {
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

    // MARK: - Diagnostics

    /// Non-blocking emit. No-op without a sink. `process`/`seq` are placeholders
    /// the `DiagnosticLog` overwrites; `Task` keeps the gesture handler unblocked.
    private func emit(_ name: String, _ payload: [String: DiagValue]) {
        guard let log = diagnosticLog else { return }
        let event = DiagnosticEvent(at: Date(), seq: 0, process: .app, category: .ui, name: name, payload: payload)
        Task { await log.log(event) }
    }

    /// Flatten a `DragTarget` to a diagnostic payload, including `.rejected`/
    /// `.none` so cancelled drags are fully visible in the log.
    static func targetPayload(_ target: DragTarget) -> [String: DiagValue] {
        switch target {
        case .between(let beforeID, let afterID, let parentID):
            return [
                "kind": .string("between"),
                "beforeID": beforeID.map { .string($0.uuidString) } ?? .null,
                "afterID": afterID.map { .string($0.uuidString) } ?? .null,
                "parentID": parentID.map { .string($0.uuidString) } ?? .null,
            ]
        case .rejected:
            return ["kind": .string("rejected")]
        case .none:
            return ["kind": .string("none")]
        }
    }
}
