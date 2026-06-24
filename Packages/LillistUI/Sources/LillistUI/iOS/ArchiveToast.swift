// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI

/// Transient "N tasks archived. Tap to undo." pill shown at the bottom of
/// the iOS Tasks screen after a pull-to-refresh archive sweep.
///
/// Auto-dismisses ~4 seconds after appearing; the entire capsule is a
/// single tappable Button so the user doesn't need to hit a small word —
/// any tap inside the pill fires `onUndo`. Bottom safe-area anchored —
/// the consumer is expected to attach this as an overlay with
/// `.overlay(alignment: .bottom) { ArchiveToast(...) }`.
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
        Group {
            if isPresented {
                Button {
                    onUndo()
                    isPresented = false
                } label: {
                    Text(labelText)
                        .font(LillistTypography.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, LillistSpacing.l)
                        .padding(.vertical, LillistSpacing.m)
                        .rainbowToastChrome()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(labelText)
                .accessibilityHint(
                    String(localized: "Restores the most recently archived tasks.",
                           bundle: .module)
                )
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
