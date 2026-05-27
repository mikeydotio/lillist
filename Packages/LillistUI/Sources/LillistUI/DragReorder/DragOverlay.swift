import SwiftUI

/// Drawn as `.overlay` on the task list container. Observes the
/// `DragController` and renders:
///
/// 1. The floating phantom row at the cursor y-position (scaled +
///    shadowed). The phantom content is provided by the screen via
///    the `phantomContent` closure so the overlay stays platform-
///    agnostic.
/// 2. The active drop indicator:
///    - `.between(...)` → a `Capsule` divider at the row boundary.
///    - `.onto(...)` → a stroked `RoundedRectangle` around the target.
///    - `.rejected` → no indicator; the phantom is bordered red.
///    - `.none` → nothing.
public struct DragOverlay<PhantomContent: View>: View {
    @ObservedObject var controller: DragController
    let phantomContent: (UUID) -> PhantomContent

    public init(
        controller: DragController,
        @ViewBuilder phantomContent: @escaping (UUID) -> PhantomContent
    ) {
        self.controller = controller
        self.phantomContent = phantomContent
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            switch controller.state {
            case .idle:
                EmptyView()
            case .dragging(let session):
                indicator(for: session.target)
                phantom(for: session)
            case .dropping(let session, _):
                phantom(for: session)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func phantom(for session: DragSession) -> some View {
        phantomContent(session.draggedID)
            .frame(height: session.originalHeight)
            .scaleEffect(LillistDragTokens.phantomScale)
            .shadow(radius: LillistDragTokens.phantomShadowRadius, y: 8)
            .opacity(LillistDragTokens.phantomOpacity)
            .overlay(
                RoundedRectangle(cornerRadius: LillistDragTokens.rowBorderCornerRadius)
                    .stroke(
                        LillistDragTokens.rejectionColor,
                        lineWidth: session.target == .rejected ? LillistDragTokens.rowBorderThickness : 0
                    )
            )
            .position(
                x: phantomCenterX,
                y: session.cursorY
            )
    }

    @ViewBuilder
    private func indicator(for target: DragTarget) -> some View {
        switch target {
        case .between(let beforeID, let afterID, _):
            betweenDivider(beforeID: beforeID, afterID: afterID)
        case .onto(let id):
            ontoBorder(targetID: id)
        case .rejected, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func betweenDivider(beforeID: UUID?, afterID: UUID?) -> some View {
        // Position the capsule at the boundary line:
        // - prefer beforeID's maxY if available
        // - else afterID's minY
        // NOTE: the anchor naming follows TaskStore.reorder semantics —
        // `beforeID` is the row the dragged row will sit BEFORE, so the
        // gap line is at beforeID.minY (above the row dragged lands above).
        // afterID is the row the dragged row will sit AFTER, so the gap
        // line is at afterID.maxY.
        let y: CGFloat? = {
            if let id = afterID,  let f = controller.geometry[id] { return f.maxY }
            if let id = beforeID, let f = controller.geometry[id] { return f.minY }
            return nil
        }()
        if let y {
            let referenceID = afterID ?? beforeID
            let frame = referenceID.flatMap { controller.geometry[$0] } ?? .zero
            Capsule()
                .fill(LillistDragTokens.indicatorColor)
                .frame(width: frame.width - 24, height: LillistDragTokens.dividerThickness)
                .position(x: 12 + (frame.width - 24) / 2, y: y)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func ontoBorder(targetID: UUID) -> some View {
        if let frame = controller.geometry[targetID] {
            let outset = LillistDragTokens.rowBorderOutset
            RoundedRectangle(cornerRadius: LillistDragTokens.rowBorderCornerRadius)
                .stroke(LillistDragTokens.indicatorColor, lineWidth: LillistDragTokens.rowBorderThickness)
                .frame(width: frame.width + outset * 2, height: frame.height + outset * 2)
                .position(x: frame.midX, y: frame.midY)
                .transition(.opacity)
        }
    }

    private var phantomCenterX: CGFloat {
        // Use the first geometry entry's midX as the phantom horizontal center.
        // All rows are full-width so any entry suffices.
        controller.geometry.values.first?.midX ?? 0
    }
}
