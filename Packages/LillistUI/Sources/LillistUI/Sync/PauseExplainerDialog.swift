import SwiftUI
import LillistCore

/// Sheet/dialog explaining why iCloud sync is paused.
///
/// Plan 21: the indicator (cloud-with-slash) is tappable across iOS
/// and macOS. The tap invokes this dialog with the active
/// `PauseReason`. Copy is sourced verbatim from the design spec's
/// truth table and matches across platforms.
///
/// The view is pure presentation — no env-coupled lifecycle. Hosts
/// pass closures: `onOpenSettings` opens the appropriate system
/// Settings (UIApplication.shared.open on iOS, NSWorkspace on macOS);
/// `onDismiss` tears down the presenting sheet.
///
/// Data-sync-hardening `S3`: for `.accountChanged` specifically, two
/// additional async-throwing closures replace what used to be a single
/// "Disable Sync" button — `onAdoptNewAccount` ("Use This Account," wired
/// to `DataStoreResetService.resolveAccountMismatchByRedownloading()`
/// then `AccountIdentityStore.adoptCurrentIdentity()`) and `onStayLocal`
/// ("Stay Local For Now," wired to `MigrationCoordinator.beginDisable
/// (strategy: .now)` then the same adopt call). Per the council decision
/// (`.council/s3-account-mismatch-response-policy/DECISION.md`), this
/// dialog stays non-blocking/dismissible even for `.accountChanged` — the
/// mid-session containment (severing a live mirroring connection) happens
/// automatically, before this dialog is ever shown, at the `AppEnvironment`
/// level; this dialog only ever offers the user's explicit *resolution*
/// choice. The dialog manages its own resolving/error state inline
/// (spinner + disabled buttons + inline error text), mirroring
/// `ResetDataStoreSection`'s existing `isResetting`/`result` pattern rather
/// than introducing a separate progress-sheet type — neither resolution
/// primitive exposes granular phase streaming the way `MigrationCoordinator
/// .progressStream` does for the other migration sheets.
public struct PauseExplainerDialog: View {
    public let reason: PauseReason
    public let onOpenSettings: () -> Void
    public let onAdoptNewAccount: () async throws -> Void
    public let onStayLocal: () async throws -> Void
    public let onDismiss: () -> Void

    @State private var isResolving = false
    @State private var resolutionError: String?

    public init(
        reason: PauseReason,
        onOpenSettings: @escaping () -> Void,
        onAdoptNewAccount: @escaping () async throws -> Void = {},
        onStayLocal: @escaping () async throws -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.reason = reason
        self.onOpenSettings = onOpenSettings
        self.onAdoptNewAccount = onAdoptNewAccount
        self.onStayLocal = onStayLocal
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(RainbowPalette.cautionAmber.ink)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(body(for: reason))
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
                if let primary = primaryAction {
                    Button(primary, action: onOpenSettings)
                        .buttonStyle(.borderedProminent)
                        .disabled(isResolving)
                }
                if reason == .accountChanged {
                    Button {
                        resolve(onAdoptNewAccount)
                    } label: {
                        if isResolving {
                            ProgressView()
                        } else {
                            Text("Use This Account")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResolving)

                    Button("Stay Local For Now") {
                        resolve(onStayLocal)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResolving)
                }
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .disabled(isResolving)
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: 420)
    }

    /// Runs a resolution closure, showing a spinner and disabling every
    /// button while it's in flight, surfacing a thrown error inline rather
    /// than dismissing — a failure must leave the dialog open so the user
    /// can retry or pick the other option.
    private func resolve(_ action: @escaping () async throws -> Void) {
        resolutionError = nil
        isResolving = true
        Task {
            do {
                try await action()
                isResolving = false
                onDismiss()
            } catch {
                isResolving = false
                resolutionError = error.localizedDescription
            }
        }
    }

    private var title: String {
        switch reason {
        case .noAccount: return String(localized: "iCloud isn't signed in", bundle: .module)
        case .restricted: return String(localized: "iCloud is restricted", bundle: .module)
        case .accountChanged: return String(localized: "iCloud account changed", bundle: .module)
        case .noNetwork: return String(localized: "No internet connection", bundle: .module)
        case .iCloudDriveDisabled: return String(localized: "iCloud Drive is off", bundle: .module)
        case .unknown: return String(localized: "Sync is paused", bundle: .module)
        }
    }

    private func body(for reason: PauseReason) -> String {
        switch reason {
        case .noAccount:
            return String(localized: "iCloud isn't signed in on this device.", bundle: .module)
        case .restricted:
            return String(localized: "iCloud isn't currently available on this device. Check Settings to see why.", bundle: .module)
        case .accountChanged:
            return String(localized: "The iCloud account signed in on this device is different from the one this device's data belongs to. Sign back into the original account in Settings, use this account and start fresh (this device's current data is backed up first), or stay in Local Only mode until you decide.", bundle: .module)
        case .noNetwork:
            return String(localized: "No internet connection. Sync will resume automatically.", bundle: .module)
        case .iCloudDriveDisabled:
            return String(localized: "iCloud Drive is turned off for Lillist.", bundle: .module)
        case .unknown:
            return String(localized: "Sync is paused. Check iCloud settings and your internet connection.", bundle: .module)
        }
    }

    private var primaryAction: String? {
        switch reason {
        case .noAccount, .restricted, .accountChanged, .iCloudDriveDisabled, .unknown:
            return String(localized: "Open Settings", bundle: .module)
        case .noNetwork:
            return nil
        }
    }
}
