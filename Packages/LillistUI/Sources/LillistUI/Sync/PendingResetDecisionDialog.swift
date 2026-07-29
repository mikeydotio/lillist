import SwiftUI
import LillistCore

/// Data-sync-hardening `S10`: the always-prompt UI for a `ResetControlEvent`
/// another device broadcast — remote reset events are NEVER auto-applied,
/// regardless of age, so this dialog is the **only** UI path that can ever
/// trigger `ResetSignalMonitor.confirmApply()`.
///
/// Mirrors `PauseExplainerDialog`'s exact shape (resolving/error state
/// managed inline — spinner + disabled buttons + inline error text —
/// rather than a separate progress-sheet type) and its non-blocking/
/// persistent presentation contract: "Not Now" only dismisses this sheet,
/// it does not decide anything — `pendingResetDecision` stays set on the
/// environment (so the badge/banner that opened this dialog remains
/// tappable), and the next `ResetSignalMonitor` scan re-evaluates the same
/// event from scratch.
public struct PendingResetDecisionDialog: View {
    public let event: ResetControlEvent
    public let onApply: () async throws -> Void
    public let onDismiss: () -> Void

    @State private var isResolving = false
    @State private var resolutionError: String?

    public init(
        event: ResetControlEvent,
        onApply: @escaping () async throws -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.event = event
        self.onApply = onApply
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(RainbowPalette.cautionAmber.ink)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let resolutionError {
                Text(resolutionError)
                    .font(.footnote)
                    .foregroundStyle(RainbowPalette.cautionAmber.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            VStack(spacing: 8) {
                Button {
                    resolve()
                } label: {
                    if isResolving {
                        ProgressView()
                    } else {
                        Text("Apply Reset", bundle: .module)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isResolving)

                Button("Not Now", action: onDismiss)
                    .buttonStyle(.bordered)
                    .disabled(isResolving)
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: 420)
    }

    /// Runs `onApply`, showing a spinner and disabling both buttons while
    /// it's in flight, surfacing a thrown error inline rather than
    /// dismissing — a failure (e.g. the destructive-op gate is held by a
    /// concurrent migration) must leave the dialog open so the user can
    /// retry once it clears.
    private func resolve() {
        resolutionError = nil
        isResolving = true
        Task {
            do {
                try await onApply()
                isResolving = false
                onDismiss()
            } catch {
                isResolving = false
                resolutionError = error.localizedDescription
            }
        }
    }

    private var title: String {
        switch event.kind {
        case .resetToEmpty:
            return String(localized: "Reset Everywhere Requested", bundle: .module)
        case .resetAndReseed:
            return String(localized: "Restore Everywhere Requested", bundle: .module)
        }
    }

    private var message: String {
        switch event.kind {
        case .resetToEmpty:
            return String(
                localized: "\(event.senderDisplayName) asked every device on this account to erase its data and start fresh. Applying this will erase this device's data too — there is nothing left to download from iCloud once every device applies. This cannot be undone.",
                bundle: .module
            )
        case .resetAndReseed:
            return String(
                localized: "\(event.senderDisplayName) asked every device on this account to adopt its data as the new source of truth. Applying this will erase this device's local data and download \(event.senderDisplayName)'s data from iCloud instead. This cannot be undone.",
                bundle: .module
            )
        }
    }
}
