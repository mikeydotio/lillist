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
    /// When `false`, a full-swipe or fast fling only *reveals* this action's
    /// button (held open) — committing it requires an explicit tap. Defaults to
    /// `true` (classic swipe-to-trigger). Set `false` to guard easy-to-misfire
    /// actions like Delete. Independent of `isDestructive`, which governs only
    /// the action's role/styling.
    public var allowsFullSwipe: Bool
    public var perform: () -> Void

    public init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        isDestructive: Bool = false,
        allowsFullSwipe: Bool = true,
        perform: @escaping () -> Void
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.isDestructive = isDestructive
        self.allowsFullSwipe = allowsFullSwipe
        self.perform = perform
    }
}

/// A row that reveals custom swipe actions — `leading` on a right-swipe,
/// `trailing` on a left-swipe — with full-swipe-to-trigger.
///
/// Cross-platform (iOS + macOS trackpad). Why custom and not `.swipeActions`:
/// this app drives row reordering with a bespoke `DragController` gesture
/// laid over the row. A SwiftUI `DragGesture` on cell content claims the
/// horizontal pan the instant the pointer lands, so the UIKit-layer
/// `.swipeActions` recognizer never fires (swipe-to-delete silently dies — the
/// bug this replaces). Arbitration is per-platform:
///   • iOS bridges the swipe to a UIKit `UIPanGestureRecognizer`
///     (`HorizontalSwipePanGesture`) whose delegate refuses to begin unless
///     the touch is predominantly horizontal, so the `List`'s scroll pan
///     claims every vertical drag at the UIKit layer. (The prior SwiftUI
///     `DragGesture` claimed the touch even while its handler yielded
///     vertical motion, blocking the scroll — issue #12.)
///   • `isReorderActive` (true once a drag is confirmed) hard-disables the
///     swipe recognizer, so a diagonal reorder can never trip an action.
///   • macOS keeps the SwiftUI `DragGesture`: it commits to an axis on first
///     movement and applies only horizontal drags, while the macOS reorder
///     `DragGesture` is axis-gated to *vertical* motion (see
///     `DragReorderable`), keeping the two mutually exclusive.
///
/// `openRowID` coordinates "only one row open at a time": opening this row
/// stamps its `rowID`, and any row whose id no longer matches snaps closed.
public struct SwipeableRow<Content: View>: View {
    let rowID: UUID
    var leading: SwipeActionSpec?
    var trailing: SwipeActionSpec?
    var isReorderActive: Bool
    @Binding var openRowID: UUID?
    @ViewBuilder var content: () -> Content

    public init(
        rowID: UUID,
        leading: SwipeActionSpec? = nil,
        trailing: SwipeActionSpec? = nil,
        isReorderActive: Bool,
        openRowID: Binding<UUID?>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.rowID = rowID
        self.leading = leading
        self.trailing = trailing
        self.isReorderActive = isReorderActive
        self._openRowID = openRowID
        self.content = content
    }

    /// Width of a revealed action card.
    private let actionWidth: CGFloat = 84
    /// Past this displacement, releasing commits the action outright.
    private let fullSwipeThreshold: CGFloat = 170
    /// Horizontal gap between the row edge and a revealed action card. Equals
    /// the inter-row vertical gap (3pt top + 3pt bottom `listRowInsets` in
    /// TasksScreen), so the revealed card is inset from the row by the same
    /// amount on every side.
    private let actionGap: CGFloat = 6
    /// Resting offset when a side is held open: the content slides this far to
    /// fully reveal an `actionWidth` card with `actionGap` of clearance behind
    /// the row's edge.
    private var revealDistance: CGFloat { actionWidth + actionGap }

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0

    #if os(macOS)
    /// Which axis the current macOS drag committed to. iOS needs no axis
    /// state: the bridged pan recognizer declines vertical touches before
    /// they ever begin.
    @State private var axis: Axis2D = .undecided

    private enum Axis2D { case undecided, horizontal, vertical }
    #endif

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion
    private var reduceMotion: Bool { overrideReduceMotion ?? systemReduceMotion }

    public var body: some View {
        ZStack {
            actionBackground
            content()
                .overlay {
                    // While open, intercept taps to close instead of letting
                    // the inner row tap open the editor. The overlay must sit
                    // *inside* the `.offset` below so it rides the same shift as
                    // the content: `.offset` moves rendering + hit region but
                    // not the layout frame, so an overlay applied *after* offset
                    // would blanket the row's full width — including the
                    // revealed action strip — and eat taps meant for the action
                    // Button (it lives in the `actionBackground` layer beneath).
                    if offset != 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                // No opaque backing needed: the content slides *away* from the
                // revealed action (opposite edge), so they never overlap, and
                // adding a fill would change the row's resting render.
                .offset(x: offset)
                #if os(iOS)
                // The `!isReorderActive` guards are NOT dead code despite
                // `isEnabled` mirroring the same flag: the recognizer is
                // disabled on SwiftUI's *next update pass*, so a UIKit event
                // already in flight when `isReorderActive` flips can still
                // arrive before `updateUIGestureRecognizer` runs.
                .gesture(HorizontalSwipePanGesture(
                    isEnabled: !isReorderActive,
                    onBegan: {
                        guard !isReorderActive else { return }
                        dragStartOffset = offset
                    },
                    onChanged: { translationX in
                        guard !isReorderActive else { return }
                        offset = resist(dragStartOffset + translationX)
                    },
                    onEnded: { predictedTranslationX in
                        guard !isReorderActive else { return }
                        settle(predictedTranslation: predictedTranslationX)
                    },
                    onCancelled: {
                        // A cancelled touch (system interruption, or the
                        // reorder-activation disable path) is not a release:
                        // restore the row, never settle — settling could
                        // commit a full-swipe action the user never chose.
                        close()
                    }
                ))
                #else
                .simultaneousGesture(swipeGesture)
                #endif
        }
        .onChange(of: openRowID) { _, newValue in
            if newValue != rowID, offset != 0 { close() }
        }
        .onChange(of: isReorderActive) { _, active in
            if active, offset != 0 { close() }
        }
    }

    // MARK: - Background reveal

    /// The revealed action layer sits *behind* the content. Each action is a
    /// fixed-width card parked off its row edge at rest and slid into view by an
    /// offset locked to the drag, so it appears to emerge from behind the row's
    /// edge (keeping `actionGap` of clearance) rather than growing out of the
    /// screen edge.
    private var actionBackground: some View {
        ZStack {
            if let leading {
                actionCard(leading, active: offset >= 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    // Parked off the leading edge at rest (offset 0); flush, with
                    // `actionGap` behind the row edge, at offset == revealDistance.
                    .offset(x: min(0, offset - revealDistance))
            }
            if let trailing {
                actionCard(trailing, active: offset <= -2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    // Parked off the trailing edge at rest; flush at
                    // offset == -revealDistance.
                    .offset(x: max(0, offset + revealDistance))
            }
        }
        // Clip parked / over-travelled cards to the row's content frame so a
        // closed row never shows a sliver of an action card in the list-row
        // inset, and the revealed card reads as sliding out from behind the
        // row's edge.
        .clipped()
    }

    @ViewBuilder
    private func actionCard(_ spec: SwipeActionSpec, active: Bool) -> some View {
        Button {
            perform(spec)
        } label: {
            ZStack {
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
            }
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Enabled only once the card has begun to reveal — reproduces the old
        // `revealed < 2` gate so the parked (off-edge) card never captures a
        // phantom tap or VoiceOver focus while the row is closed.
        .disabled(!active)
        .accessibilityLabel(Text(spec.titleKey, bundle: .module))
        .clipShape(RoundedRectangle(cornerRadius: LillistRadius.m, style: .continuous))
    }

    // MARK: - Gesture (macOS trackpad)

    #if os(macOS)
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
    #endif

    /// Clamp to the available actions, with rubber-band resistance past the
    /// resting reveal width (and near-total resistance toward a side with no
    /// action).
    private func resist(_ x: CGFloat) -> CGFloat {
        if x > 0 {
            guard leading != nil else { return x * 0.05 }
            return x <= revealDistance ? x : revealDistance + (x - revealDistance) * 0.3
        } else if x < 0 {
            guard trailing != nil else { return x * 0.05 }
            return x >= -revealDistance ? x : -revealDistance + (x + revealDistance) * 0.3
        }
        return 0
    }

    private func settle(predictedTranslation: CGFloat) {
        // Decision (commit/open/close) lives in the pure `SwipeSettleArbiter`;
        // this method only performs the resulting side effects.
        let outcome = SwipeSettleArbiter.outcome(
            offset: offset,
            predictedTranslation: predictedTranslation,
            // The resting reveal is the card plus its gap; the arbiter's
            // "open past half" threshold keys off this distance.
            actionWidth: revealDistance,
            fullSwipeThreshold: fullSwipeThreshold,
            hasLeading: leading != nil,
            leadingAllowsFullSwipe: leading?.allowsFullSwipe ?? false,
            hasTrailing: trailing != nil,
            trailingAllowsFullSwipe: trailing?.allowsFullSwipe ?? false
        )
        switch outcome {
        case .commitTrailing:
            if let trailing { perform(trailing) }
        case .commitLeading:
            if let leading { perform(leading) }
        case .openTrailing:
            snap(to: -revealDistance)
            openRowID = rowID
        case .openLeading:
            snap(to: revealDistance)
            openRowID = rowID
        case .close:
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
