import Foundation

/// Testable seam over reachability so the classifier doesn't depend
/// on Network.framework directly.
public protocol NetworkReachabilityProviding: Sendable {
    /// `true` when a usable internet path is available.
    func isReachable() async -> Bool
}

/// A reachability provider that always reports the value handed in
/// at init. Useful for tests and the truth-table cases below.
public struct ConstantNetworkReachability: NetworkReachabilityProviding {
    public let reachable: Bool
    public init(reachable: Bool) { self.reachable = reachable }
    public func isReachable() async -> Bool { reachable }
}

/// Maps the current account / network / drive state to a single
/// `PauseReason`. Used by the status badge and the explainer dialog.
///
/// Priority order (high → low) per the Plan 21 spec table:
///
///   `.accountChanged` → `.noAccount` → `.restricted` →
///   `.iCloudDriveDisabled` → `.noNetwork` → `.unknown`
///
/// The classifier is an actor not because of shared mutable state
/// (it has none) but to match the rest of the Sync subsystem; future
/// extensions may cache the last-classified reason.
public actor PauseReasonClassifier {
    private let accountMonitor: AccountStateMonitor
    private let networkMonitor: any NetworkReachabilityProviding
    /// Data-sync-hardening `S24`: pull-based replacement for the old
    /// `setICloudDriveDisabled(_:)` push API, which no production call
    /// site ever actually called — `.iCloudDriveDisabled` was unreachable
    /// dead code. Reuses `AccountIdentityStore`'s own probe seam
    /// (`FileManager.ubiquityIdentityToken`): when the base account state
    /// is `.available` (a real CloudKit account is signed in) but the
    /// ubiquity token is `nil`, that's precisely Apple's documented
    /// distinction between "an iCloud account is signed in" and "this app
    /// has iCloud Drive/ubiquity access" — no separately-tracked mutable
    /// bit is needed, and there's no "forgot to call the setter" failure
    /// mode to reintroduce.
    private let identityProbe: any AccountIdentityProbing

    public init(
        accountMonitor: AccountStateMonitor,
        networkMonitor: any NetworkReachabilityProviding,
        identityProbe: any AccountIdentityProbing = UbiquityIdentityProbe()
    ) {
        self.accountMonitor = accountMonitor
        self.networkMonitor = networkMonitor
        self.identityProbe = identityProbe
    }

    /// Compute the current pause reason, or `nil` when sync is
    /// active.
    public func currentReason() async -> PauseReason? {
        let state = await accountMonitor.currentState
        switch state {
        case .accountChanged:
            return .accountChanged
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .available:
            break
        }
        if identityProbe.currentIdentity() == nil { return .iCloudDriveDisabled }
        if await !networkMonitor.isReachable() { return .noNetwork }
        return nil
    }
}
