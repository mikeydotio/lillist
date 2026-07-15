import SwiftUI
import LillistCore

/// Clickable status indicator per design Section 7.
///
/// Tap fires `onClick` (the forward-only advance from `StatusCycler.nextOnClick`:
/// todo → started → closed, with closed terminal). Long-press expands an inline
/// menu of explicit setters — Started, Blocked, Closed — wired through
/// `onSetStatus`. The Plan 13 a11y action "Cycle status" still drives the same
/// path so AT users get the same behaviour as a tap.
///
/// Plan 18 swapped the underlying gesture from `simultaneousGesture(LongPressGesture)`
/// on a `.plain` Button to `Menu(primaryAction:)`. The simultaneous gesture
/// was widely flaky — the Button could swallow the press depending on
/// duration. See `docs/engineering-notes.md` entry "Plan 18 iOS polish sweep".
public struct StatusIndicatorView: View {
    public var status: Status
    public var onClick: () -> Void
    public var onSetStatus: (Status) -> Void

    public init(
        status: Status,
        onClick: @escaping () -> Void,
        onSetStatus: @escaping (Status) -> Void
    ) {
        self.status = status
        self.onClick = onClick
        self.onSetStatus = onSetStatus
    }

    public var body: some View {
        // Rainbow Logic: the 3D status cube is the visual; the Menu sits
        // above it as a transparent hit layer. The cube must NOT be the
        // Menu's label — macOS renders Menu labels through machinery
        // that drops Shape fills in hosted/headless contexts (Images
        // survive, fills vanish), so a cube-as-label draws as a bare
        // checkmark. A plain view + clear-label Menu renders identically
        // everywhere. The Menu structure, identifier, traits, and 44pt
        // hit target are the StatusCycleUITests-pinned contract.
        StatusCubeView(status: status)
            .frame(width: 44, height: 44)
            .overlay {
                Menu {
                    Button {
                        onSetStatus(.started)
                    } label: {
                        Label(StatusGlyph.accessibilityLabel(for: .started),
                              systemImage: StatusGlyph.symbol(for: .started))
                    }
                    Button {
                        onSetStatus(.blocked)
                    } label: {
                        Label(StatusGlyph.accessibilityLabel(for: .blocked),
                              systemImage: StatusGlyph.symbol(for: .blocked))
                    }
                    Button {
                        onSetStatus(.closed)
                    } label: {
                        Label(StatusGlyph.accessibilityLabel(for: .closed),
                              systemImage: StatusGlyph.symbol(for: .closed))
                    }
                } label: {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                } primaryAction: {
                    onClick()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)  // hide the macOS disclosure chevron — the cube is the affordance
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            // Collapse the cube + Menu overlay into ONE accessibility element at
            // the 44pt frame. Without this the control exposes several competing
            // elements (the cube's shapes, the `.closed` state's implicit
            // `checkmark` image, the Menu button); XCUITest's `StatusIndicator`
            // firstMatch then resolves to a sub-44pt element that is occluded by
            // the Menu overlay or collapses to the ~10pt checkmark — leaving the
            // control un-hittable on a Closed row and below Apple's 44pt HIG floor
            // (issue #15). One ignored-children leaf keeps a stable 44pt hit
            // target in every state; real touches still reach the Menu hit layer.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("StatusIndicator")
            .accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))
            .accessibilityAddTraits(.isButton)
            // Default activation (VoiceOver double-tap) cycles, matching a tap.
            .accessibilityAction {
                onClick()
            }
            .accessibilityAction(named: Text(String(localized: "Cycle status", bundle: .module))) {
                onClick()
            }
            // Ignoring children drops the Menu's setters from the a11y tree, so
            // re-expose them as named actions (reusing the existing status labels)
            // — AT users keep the long-press menu's Started/Blocked/Closed choices.
            .accessibilityAction(named: Text(StatusGlyph.accessibilityLabel(for: .started))) {
                onSetStatus(.started)
            }
            .accessibilityAction(named: Text(StatusGlyph.accessibilityLabel(for: .blocked))) {
                onSetStatus(.blocked)
            }
            .accessibilityAction(named: Text(StatusGlyph.accessibilityLabel(for: .closed))) {
                onSetStatus(.closed)
            }
    }
}
