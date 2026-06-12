import SwiftUI
import LillistCore

/// Clickable status indicator per design Section 7.
///
/// Tap fires `onClick` (the cycle contract from `StatusCycler.nextOnClick`).
/// Long-press expands an inline menu of explicit setters — Started, Blocked,
/// Closed — wired through `onSetStatus`. The Plan 13 a11y action
/// "Cycle status" still drives the cycle path so AT users get the same
/// behaviour as a tap.
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
            Image(systemName: StatusGlyph.symbol(for: status))
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(StatusPalette.color(for: status))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        } primaryAction: {
            onClick()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)  // hide the macOS disclosure chevron — the glyph is the affordance
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .accessibilityIdentifier("StatusIndicator")
        .accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(String(localized: "Cycle status", bundle: .module))) {
            onClick()
        }
    }
}
