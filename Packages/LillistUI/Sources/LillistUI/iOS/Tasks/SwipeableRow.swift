#if os(iOS)
import SwiftUI

/// One swipe action — the colored button revealed behind a row.
///
/// `tint` is the fully-saturated background; the label renders white on top.
/// `perform` runs on a full-swipe *or* a tap of the revealed button.
public struct SwipeActionSpec {
    public var titleKey: LocalizedStringKey
    public var systemImage: String
    public var tint: Color
    public var isDestructive: Bool
    public var perform: () -> Void

    public init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        isDestructive: Bool = false,
        perform: @escaping () -> Void
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.isDestructive = isDestructive
        self.perform = perform
    }
}

/// A row that reveals custom swipe actions — `leading` on a right-swipe,
/// `trailing` on a left-swipe — with full-swipe-to-trigger.
///
/// Why custom and not `.swipeActions`: this app drives row reordering with a
/// bespoke `DragController` long-press `DragGesture` laid over the row. A
/// SwiftUI `DragGesture` on cell content claims the horizontal pan the
/// instant the finger lands, so the UIKit-layer `.swipeActions` recognizer
/// never fires (swipe-to-delete silently dies — the bug this replaces). By
/// owning *both* gestures we make arbitration deterministic:
///   • The reorder gesture requires a 0.3 s long-press first; a quick
///     horizontal flick fails it and is read as a swipe instead.
///   • `isReorderActive` (true once a drag is confirmed) hard-disables the
///     swipe gesture, so a diagonal reorder can never trip an action.
///   • The swipe gesture commits to an axis on first movement and yields
///     vertical drags to the enclosing `List`'s scroll (it runs as a
///     `simultaneousGesture`, so the scroll is never starved).
///
/// `openRowID` coordinates "only one row open at a time": opening this row
/// stamps its `rowID`, and any row whose id no longer matches snaps closed.
struct SwipeableRow<Content: View>: View {
    let rowID: UUID
    var leading: SwipeActionSpec?
    var trailing: SwipeActionSpec?
    var isReorderActive: Bool
    @Binding var openRowID: UUID?
    @ViewBuilder var content: () -> Content

    /// Resting reveal width when an action is held open.
    private let actionWidth: CGFloat = 84
    /// Past this displacement, releasing commits the action outright.
    private let fullSwipeThreshold: CGFloat = 170

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var axis: Axis2D = .undecided

    private enum Axis2D { case undecided, horizontal, vertical }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion
    private var reduceMotion: Bool { overrideReduceMotion ?? systemReduceMotion }

    var body: some View {
        ZStack {
            actionBackground
            content()
                // No opaque backing needed: the content slides *away* from the
                // revealed action (opposite edge), so they never overlap, and
                // adding a fill would change the row's resting render.
                .offset(x: offset)
                .overlay {
                    // While open, intercept taps to close instead of letting
                    // the inner row tap open the editor.
                    if offset != 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                .simultaneousGesture(swipeGesture)
        }
        .onChange(of: openRowID) { _, newValue in
            if newValue != rowID, offset != 0 { close() }
        }
        .onChange(of: isReorderActive) { _, active in
            if active, offset != 0 { close() }
        }
    }

    // MARK: - Background reveal

    private var actionBackground: some View {
        HStack(spacing: 0) {
            if let leading {
                actionButton(leading, revealed: max(0, offset), alignment: .leading)
            }
            Spacer(minLength: 0)
            if let trailing {
                actionButton(trailing, revealed: max(0, -offset), alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ spec: SwipeActionSpec, revealed: CGFloat, alignment: Alignment) -> some View {
        Button {
            perform(spec)
        } label: {
            ZStack(alignment: alignment) {
                spec.tint
                Label {
                    Text(spec.titleKey, bundle: .module)
                        .font(LillistTypography.caption2)
                } icon: {
                    Image(systemName: spec.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(width: revealed)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(revealed < 2)
        .accessibilityLabel(Text(spec.titleKey, bundle: .module))
        .clipShape(RoundedRectangle(cornerRadius: LillistRadius.m, style: .continuous))
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isReorderActive else { return }
                if axis == .undecided {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) >= 10 else { return }
                    axis = dx > dy ? .horizontal : .vertical
                    dragStartOffset = offset
                }
                guard axis == .horizontal else { return }   // vertical → let the List scroll
                offset = resist(dragStartOffset + value.translation.width)
            }
            .onEnded { value in
                defer { axis = .undecided }
                guard axis == .horizontal, !isReorderActive else { return }
                settle(predictedTranslation: value.predictedEndTranslation.width)
            }
    }

    /// Clamp to the available actions, with rubber-band resistance past the
    /// resting reveal width (and near-total resistance toward a side with no
    /// action).
    private func resist(_ x: CGFloat) -> CGFloat {
        if x > 0 {
            guard leading != nil else { return x * 0.05 }
            return x <= actionWidth ? x : actionWidth + (x - actionWidth) * 0.3
        } else if x < 0 {
            guard trailing != nil else { return x * 0.05 }
            return x >= -actionWidth ? x : -actionWidth + (x + actionWidth) * 0.3
        }
        return 0
    }

    private func settle(predictedTranslation: CGFloat) {
        // Full-swipe: a strong fling or a long pull commits the action.
        if offset <= -fullSwipeThreshold || predictedTranslation <= -fullSwipeThreshold * 1.4,
           let trailing {
            perform(trailing)
            return
        }
        if offset >= fullSwipeThreshold || predictedTranslation >= fullSwipeThreshold * 1.4,
           let leading {
            perform(leading)
            return
        }
        // Otherwise snap open (held) or closed.
        if offset <= -actionWidth / 2, trailing != nil {
            snap(to: -actionWidth)
            openRowID = rowID
        } else if offset >= actionWidth / 2, leading != nil {
            snap(to: actionWidth)
            openRowID = rowID
        } else {
            close()
        }
    }

    // MARK: - Animated transitions

    private func perform(_ spec: SwipeActionSpec) {
        // Close first so the row is visually settled before the data mutates.
        close()
        spec.perform()
    }

    private func close() {
        snap(to: 0)
        if openRowID == rowID { openRowID = nil }
    }

    private func snap(to target: CGFloat) {
        if reduceMotion {
            offset = target
        } else {
            withAnimation(LillistMotion.squish(LillistMotion.fast)) { offset = target }
        }
    }
}
#endif
