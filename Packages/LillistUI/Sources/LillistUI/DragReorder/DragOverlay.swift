import SwiftUI

/// Drawn as `.overlay` on the task list container. Observes the
/// `DragController` and renders:
///
/// 1. The floating phantom row, positioned at the cursor while
///    dragging and at the resolved settle position while dropping.
///    The phantom content is supplied by the screen via the
///    `phantomContent` closure so the overlay stays platform-agnostic.
///    A single phantom view persists across the `.dragging → .dropping`
///    transition so SwiftUI can interpolate its scale, opacity, and
///    position into the settle.
/// 2. The active drop indicator (during `.dragging` only):
///    - `.between(...)` → a `Capsule` divider at the row boundary, indented to
///      the depth the row will land at.
///    - `.rejected`     → no indicator; the phantom is bordered red.
///    - `.none`         → nothing.
public struct DragOverlay<PhantomContent: View>: View {
    @ObservedObject var controller: DragController
    let phantomContent: (UUID) -> PhantomContent
    /// Maps a reference row's frame + depth and the drop's target depth to the
    /// leading x of the between-divider, so the indicator renders at the
    /// indentation the dragged row will land at. Platform-specific because iOS
    /// renders depth *inside* a full-width row (frames are depth-invariant)
    /// while macOS `OutlineGroup` shifts each row's frame. Defaults to the iOS
    /// formula; macOS passes its own.
    let indentLeadingX: (_ referenceFrame: CGRect, _ referenceDepth: Int, _ targetDepth: Int) -> CGFloat

    public init(
        controller: DragController,
        indentLeadingX: @escaping (_ referenceFrame: CGRect, _ referenceDepth: Int, _ targetDepth: Int) -> CGFloat = { frame, _, targetDepth in
            // Leading edge of the dragged row's slot at `targetDepth`, matching
            // the row's own indentation (`TaskOutlineRowView` indents by
            // `indentPerLevel` per level from `frame.minX`). No extra inset —
            // the line's leading edge lands exactly where the dropped row's
            // leading edge will be.
            frame.minX + CGFloat(targetDepth) * LillistDragTokens.indentPerLevel
        },
        @ViewBuilder phantomContent: @escaping (UUID) -> PhantomContent
    ) {
        self.controller = controller
        self.indentLeadingX = indentLeadingX
        self.phantomContent = phantomContent
    }

    public var body: some View {
        // The `.coordinateSpace(name:)` is anchored on the List (which
        // extends behind safe areas), but the `.overlay { … }` content
        // is laid out *inside* the safe area, so the overlay's local
        // coord space and the named coord space have different
        // anchors. `controller.geometry` frames are reported in the
        // named space; `.position(y:)` calls inside this overlay
        // interpret y in *overlay-local* space. A `-dy` shift converts
        // named → local at runtime so the two stay in lockstep no
        // matter what the safe-area insets are doing.
        GeometryReader { proxy in
            let dy = proxy.frame(in: .named(DragCoordinateSpace.name)).minY

            ZStack(alignment: .topLeading) {
                if let session = activeSession {
                    Group {
                        if case .dragging = controller.state {
                            indicator(for: session.target, draggedID: session.draggedID)
                        }
                        phantom(for: session)
                            .transition(.lift)
                    }
                    .offset(y: -dy)
                }
            }
            .allowsHitTesting(false)
            .accessibleAnimation(
                .easeInOut(duration: LillistDragTokens.liftDuration),
                value: phantomPresent
            )
            .accessibleAnimation(
                .easeInOut(duration: LillistDragTokens.settleDuration),
                value: settlePhase
            )
        }
    }

    // MARK: - Derived state

    /// The session backing the in-flight phantom, if any. Persists
    /// across `.dragging → .dropping` so the phantom view keeps the
    /// same SwiftUI identity and its modifiers animate rather than
    /// being recreated.
    private var activeSession: DragSession? {
        switch controller.state {
        case .idle:                 return nil
        case .dragging(let s):      return s
        case .dropping(let s, _):   return s
        }
    }

    /// The drop target the overlay is currently honoring. Used to drive
    /// the rejection stroke on the phantom and the settle destination
    /// during `.dropping`.
    private var activeTarget: DragTarget {
        switch controller.state {
        case .dragging(let s):      return s.target
        case .dropping(_, let t):   return t
        case .idle:                 return .none
        }
    }

    /// Discrete animation key — flips when the controller transitions
    /// from the lifted (`.dragging`) phase to the settling (`.dropping`)
    /// phase. Keying `.animation(_:value:)` on this — rather than on
    /// `cursorY` or the whole `state` — confines interpolation to the
    /// settle, leaving cursor tracking 1:1 with the finger.
    private var settlePhase: Bool {
        if case .dropping = controller.state { return true }
        return false
    }

    private var isSettling: Bool { settlePhase }

    /// Tracks the *existence* of an active drag (the phantom view).
    /// Flips when the controller transitions `.idle ↔ .dragging` (or
    /// `.idle ↔ .dropping`), giving the lift insertion transition an
    /// animation context to run within.
    private var phantomPresent: Bool { activeSession != nil }

    // MARK: - Phantom

    @ViewBuilder
    private func phantom(for session: DragSession) -> some View {
        let scale: CGFloat = isSettling ? 1.0 : LillistDragTokens.phantomLiftedScale
        let opacity: Double = isSettling ? 1.0 : LillistDragTokens.phantomLiftedOpacity
        let shadow: CGFloat = isSettling ? 0 : LillistDragTokens.phantomShadowRadius
        let yOffset: CGFloat = isSettling ? 0 : LillistDragTokens.phantomShadowYOffset
        let y: CGFloat = isSettling
            ? settleY(for: session, target: activeTarget)
            : session.cursorY

        // The rainbow border is the phantom card's *own* border (the screen
        // builds `phantomContent` with `.rainbowCard(border: .rainbow)`), so no
        // separate overlay stroke floats around the lifted cell.
        phantomContent(session.draggedID)
            .frame(height: session.originalHeight)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: .black.opacity(0.22), radius: shadow, y: yOffset)
            .position(
                x: phantomCenterX,
                y: y
            )
    }

    /// Computes where the phantom should land as the drag releases.
    ///
    /// - `.between(beforeID, afterID, _)` resolves to the boundary line
    ///   of the gap (just below `afterID` if known, else just above
    ///   `beforeID`).
    /// - `.rejected` and `.none` resolve to the session's
    ///   `initialCursorY` — the source row's natural center — so the
    ///   phantom appears to bounce back.
    ///
    /// Exposed as `nonisolated static` so tests can call it without
    /// rendering the overlay; `geometry` is the same dictionary the
    /// controller publishes.
    nonisolated public static func settlePosition(
        for session: DragSession,
        target: DragTarget,
        geometry: [UUID: CGRect]
    ) -> CGFloat {
        switch target {
        case .between(let beforeID, let afterID, _):
            if let id = afterID, let frame = geometry[id] {
                return frame.maxY + session.originalHeight / 2
            }
            if let id = beforeID, let frame = geometry[id] {
                return frame.minY - session.originalHeight / 2
            }
            return session.initialCursorY
        case .rejected, .none:
            return session.initialCursorY
        }
    }

    /// Settle target for the phantom on release. `.between` settles to the same
    /// insertion line the indicator shows (the current fencepost under the
    /// finger) so the lifted card doesn't jump to a different gap during the
    /// settle. `.rejected` / `.none` bounce back to the source row.
    private func settleY(for session: DragSession, target: DragTarget) -> CGFloat {
        if case .between = target,
           let y = controller.insertionIndicatorY(forCursorY: session.cursorY, draggedID: session.draggedID) {
            return y
        }
        return Self.settlePosition(for: session, target: target, geometry: controller.geometry)
    }

    // MARK: - Indicators

    @ViewBuilder
    private func indicator(for target: DragTarget, draggedID: UUID) -> some View {
        switch target {
        case .between(_, _, let parentID):
            betweenDivider(parentID: parentID, draggedID: draggedID)
        case .rejected, .none:
            EmptyView()
        }
    }

    /// The between-row divider. Its **vertical** position is the insertion
    /// fencepost nearest the touch in the *current* list
    /// (`insertionIndicatorY`), and its **leading edge** is indented to the
    /// depth the row will land at (`indentLeadingX`) — the two are independent
    /// so the line tracks the finger while previewing the drop depth.
    @ViewBuilder
    private func betweenDivider(parentID: UUID?, draggedID: UUID) -> some View {
        // Any visible row supplies the horizontal extent (all rows are
        // full-width with the same min/maxX; on macOS the reference row's depth
        // is folded into `indentLeadingX`). Prefer the parent (its depth anchors
        // the macOS inset math); fall back to the first known frame.
        let referenceID = parentID ?? controller.flatRows.first?.id
        if let cursorY = activeCursorY,
           let y = controller.insertionIndicatorY(forCursorY: cursorY, draggedID: draggedID),
           let referenceID,
           let frame = controller.geometry[referenceID] {
            let referenceDepth = controller.flatRows.first(where: { $0.id == referenceID })?.depth ?? 0
            let targetDepth = depth(forParentID: parentID)
            let leadingX = indentLeadingX(frame, referenceDepth, targetDepth)
            let trailingX = frame.maxX - LillistDragTokens.dividerHorizontalInset
            let width = max(0, trailingX - leadingX)
            Capsule()
                .fill(LillistDragTokens.indicatorColor)
                .frame(width: width, height: LillistDragTokens.dividerThickness)
                .position(x: leadingX + width / 2, y: y)
                .transition(.opacity)
        }
    }

    /// The current drag cursor Y, if a drag is in flight.
    private var activeCursorY: CGFloat? {
        switch controller.state {
        case .dragging(let s), .dropping(let s, _): return s.cursorY
        case .idle: return nil
        }
    }

    /// Depth the dragged row will land at, from the resolved target parent:
    /// top level (nil parent) is 0, otherwise the parent's depth + 1.
    private func depth(forParentID parentID: UUID?) -> Int {
        guard let parentID,
              let parentRow = controller.flatRows.first(where: { $0.id == parentID })
        else { return 0 }
        return parentRow.depth + 1
    }

    private var phantomCenterX: CGFloat {
        // Use the first geometry entry's midX as the phantom horizontal center.
        // All rows are full-width so any entry suffices.
        controller.geometry.values.first?.midX ?? 0
    }
}

// MARK: - Lift transition

extension AnyTransition {
    /// **Insertion** (`.idle → .dragging`): the phantom enters at the row's
    /// *natural* scale and animates to the lifted scale — no fade. With the
    /// lifted scale at `1.0` (no shrink) this is effectively identity: the
    /// cell appears full-size in place, gains its shadow, and tracks the
    /// finger — a clean lift with no fly-in. (The inverse-scale composition is
    /// retained so reintroducing a shrink via `phantomLiftedScale` animates the
    /// resize rather than popping.)
    ///
    /// **Removal** (`.dropping → .idle`): identity — the phantom has already
    /// animated to its settle position during `.dropping`, so the unmount is
    /// instantaneous and the user only sees the in-tree settle.
    static var lift: AnyTransition {
        let inverseScale = 1.0 / LillistDragTokens.phantomLiftedScale
        return .asymmetric(
            insertion: .modifier(
                active: LiftInsertionModifier(scaleMultiplier: inverseScale),
                identity: LiftInsertionModifier(scaleMultiplier: 1.0)
            ),
            removal: .identity
        )
    }
}

/// Multiplies the existing scale via an *additional* `scaleEffect`,
/// used by the lift insertion transition to cancel the permanently-
/// applied lifted scale during the animation's active frame.
private struct LiftInsertionModifier: ViewModifier {
    let scaleMultiplier: CGFloat

    func body(content: Content) -> some View {
        content.scaleEffect(scaleMultiplier)
    }
}
