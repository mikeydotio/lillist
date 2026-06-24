// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI

/// Transient bottom-anchored failure pill. Auto-dismisses after ~4
/// seconds. No undo action — callers reload automatically and the
/// failure is transient. Attach as
/// `.overlay(alignment: .bottom) { TransientFailureToast(...) }`.
public struct TransientFailureToast: View {
    @Binding public var isPresented: Bool
    public let message: String

    public init(isPresented: Binding<Bool>, message: String) {
        self._isPresented = isPresented
        self.message = message
    }

    public var body: some View {
        Group {
            if isPresented {
                Text(message)
                .font(LillistTypography.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, LillistSpacing.l)
                .padding(.vertical, LillistSpacing.m)
                .rainbowToastChrome()
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

/// "Couldn't move that item. Please try again." — shown when a
/// drag-reorder write fails (e.g. stale anchor after a CloudKit merge).
public struct ReorderFailureToast: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        TransientFailureToast(
            isPresented: $isPresented,
            message: String(
                localized: "Couldn't move that item. Please try again.",
                bundle: .module
            )
        )
    }
}

/// "Couldn't update that task. Please try again." — shown when a
/// status transition write fails. Part of the silent-failure hardening
/// from the dead-status-tap RCA: a failed completion tap must never
/// again be indistinguishable from a dead one.
public struct StatusChangeFailureToast: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        TransientFailureToast(
            isPresented: $isPresented,
            message: String(
                localized: "Couldn't update that task. Please try again.",
                bundle: .module
            )
        )
    }
}
