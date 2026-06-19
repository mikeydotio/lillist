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
            frame.minX + LillistDragTokens.dividerHorizontalInset
                + CGFloat(targetDepth) * LillistDragTokens.indentPerLevel
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
                            indicator(for: session.target)
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
            ? Self.settlePosition(for: session, target: activeTarget, geometry: controller.geometry)
            : session.cursorY

        phantomContent(session.draggedID)
            .frame(height: session.originalHeight)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: .black.opacity(0.22), radius: shadow, y: yOffset)
            .overlay(
                // Rainbow halo on the lifted card — the drag is the one
                // surface where the halo shows on iPhone. Fades out as
                // the phantom settles.
                RoundedRectangle(cornerRadius: LillistDragTokens.rowBorderCornerRadius, style: .continuous)
                    .strokeBorder(RainbowGradient.halo, lineWidth: 1.5)
                    .opacity(isSettling ? 0 : LillistDragTokens.phantomHaloOpacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LillistDragTokens.rowBorderCornerRadius)
                    .stroke(
                        LillistDragTokens.rejectionColor,
                        lineWidth: activeTarget == .rejected ? LillistDragTokens.rowBorderThickness : 0
                    )
            )
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

    // MARK: - Indicators

    @ViewBuilder
    private func indicator(for target: DragTarget) -> some View {
        switch target {
        case .between(let beforeID, let afterID, let parentID):
            betweenDivider(beforeID: beforeID, afterID: afterID, parentID: parentID)
        case .rejected, .none:
            EmptyView()
        }
    }

    /// The between-row divider, drawn at the gap boundary and **indented to the
    /// depth the row will land at** (`indentLeadingX`). The boundary line is
    /// `afterID.maxY` (sit after that row), else `beforeID.minY` (sit before it),
    /// else — when there is no sibling anchor (first/only child of `parentID`) —
    /// just below the parent row.
    @ViewBuilder
    private func betweenDivider(beforeID: UUID?, afterID: UUID?, parentID: UUID?) -> some View {
        let referenceID = afterID ?? beforeID ?? parentID
        if let referenceID, let frame = controller.geometry[referenceID] {
            let y: CGFloat = {
                if afterID != nil { return frame.maxY }   // sit after the anchor
                if beforeID != nil { return frame.minY }  // sit before the anchor
                return frame.maxY                         // first child: below the parent
            }()
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
    /// **Insertion** (`.idle → .dragging`): the phantom enters at the
    /// row's *natural* scale/opacity and animates down to the lifted
    /// values — the visible "lift" the user sees on long-press.
    ///
    /// SwiftUI's `scaleEffect` composes multiplicatively, so the
    /// insertion is built by adding an *inverse* `scaleEffect` on top
    /// of the permanently-applied lifted `scaleEffect`: at the active
    /// state the inverse cancels the lifted scale (composite = 1.0),
    /// and at the identity state the inverse is 1.0 (composite = the
    /// lifted scale). Opacity is animated via the built-in `.opacity`
    /// transition; the phantom emerges as the source row is hidden.
    ///
    /// **Removal** (`.dropping → .idle`): identity — the phantom has
    /// already animated to natural appearance and settle position
    /// during `.dropping`, so the actual unmount is instantaneous and
    /// the user only sees the in-tree settle.
    static var lift: AnyTransition {
        let inverseScale = 1.0 / LillistDragTokens.phantomLiftedScale
        return .asymmetric(
            insertion: .modifier(
                active: LiftInsertionModifier(scaleMultiplier: inverseScale),
                identity: LiftInsertionModifier(scaleMultiplier: 1.0)
            ).combined(with: .opacity),
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
