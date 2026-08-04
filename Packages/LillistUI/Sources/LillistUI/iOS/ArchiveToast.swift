// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI

/// Transient bottom-anchored pill with a tap-to-undo action. Auto-dismisses
/// ~4 seconds after appearing; the entire capsule is a single tappable
/// Button so the user doesn't need to hit a small word — any tap inside the
/// pill fires `onUndo`. Bottom safe-area anchored — the consumer is
/// expected to attach this as an overlay with
/// `.overlay(alignment: .bottom) { TransientUndoToast(...) }`.
///
/// Shared base for every "N things happened, tap to undo" pill
/// (`ArchiveToast`, `CascadeCompleteToast`) — same factoring as
/// `TransientFailureToast` in `ReorderFailureToast.swift` for the no-undo
/// failure case.
public struct TransientUndoToast: View {
    @Binding public var isPresented: Bool
    public let message: String
    public let accessibilityHint: String
    public let onUndo: () -> Void

    public init(
        isPresented: Binding<Bool>,
        message: String,
        accessibilityHint: String,
        onUndo: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.message = message
        self.accessibilityHint = accessibilityHint
        self.onUndo = onUndo
    }

    public var body: some View {
        Group {
            if isPresented {
                Button {
                    onUndo()
                    isPresented = false
                } label: {
                    Text(message)
                        .font(LillistTypography.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, LillistSpacing.l)
                        .padding(.vertical, LillistSpacing.m)
                        .rainbowToastChrome()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(message)
                .accessibilityHint(accessibilityHint)
                .padding(.bottom, LillistSpacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: isPresented) {
                    guard isPresented else { return }
                    try? await Task.sleep(for: .seconds(4))
                    if !Task.isCancelled, isPresented {
                        isPresented = false
                    }
                }
            }
        }
        .accessibleAnimation(
            .spring(response: 0.32, dampingFraction: 0.85),
            value: isPresented
        )
    }
}

/// "N tasks archived. Tap to undo." pill shown at the bottom of the iOS
/// Tasks screen after a pull-to-refresh archive sweep.
public struct ArchiveToast: View {
    public var count: Int
    @Binding public var isPresented: Bool
    public var onUndo: () -> Void

    public init(count: Int, isPresented: Binding<Bool>, onUndo: @escaping () -> Void) {
        self.count = count
        self._isPresented = isPresented
        self.onUndo = onUndo
    }

    public var body: some View {
        TransientUndoToast(
            isPresented: $isPresented,
            message: labelText,
            accessibilityHint: String(
                localized: "Restores the most recently archived tasks.",
                bundle: .module
            ),
            onUndo: onUndo
        )
    }

    /// Plural-aware label. Two distinct localized templates so translators
    /// can adapt each form to their language's grammar without a runtime
    /// pluralization layer; %lld interpolation keeps the numeric form
    /// extractable by `xcstrings`.
    private var labelText: String {
        if count == 1 {
            return String(localized: "1 task archived. Tap to undo.",
                          bundle: .module)
        }
        return String(
            format: String(localized: "%lld tasks archived. Tap to undo.",
                           bundle: .module),
            count
        )
    }
}

/// "N subtasks completed. Tap to undo." pill shown when completing a
/// parent task cascades onto its open subtasks (LIL-97) — so a user
/// surprised by the cascade can put the subtasks back exactly as they
/// were, without hunting each one down individually.
public struct CascadeCompleteToast: View {
    public var count: Int
    @Binding public var isPresented: Bool
    public var onUndo: () -> Void

    public init(count: Int, isPresented: Binding<Bool>, onUndo: @escaping () -> Void) {
        self.count = count
        self._isPresented = isPresented
        self.onUndo = onUndo
    }

    public var body: some View {
        TransientUndoToast(
            isPresented: $isPresented,
            message: labelText,
            accessibilityHint: String(
                localized: "Reopens the subtasks that were completed along with their parent.",
                bundle: .module
            ),
            onUndo: onUndo
        )
    }

    private var labelText: String {
        if count == 1 {
            return String(localized: "1 subtask completed. Tap to undo.",
                          bundle: .module)
        }
        return String(
            format: String(localized: "%lld subtasks completed. Tap to undo.",
                           bundle: .module),
            count
        )
    }
}
