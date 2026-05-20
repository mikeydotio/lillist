import Foundation

/// Testable seam over reachability so the classifier doesn't depend
/// on Network.framework directly. The real implementation lives in
/// the app target (NWPathMonitor doesn't compile cleanly into a
/// strict-concurrency LillistCore source target without extra work,
/// and the classifier only needs a yes/no answer).
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
    /// Set by the app when it detects the user has disabled iCloud
    /// Drive for Lillist via Settings. `nil` means "we don't know"
    /// (treated as enabled for classification purposes).
    private var iCloudDriveDisabled: Bool = false

    public init(
        accountMonitor: AccountStateMonitor,
        networkMonitor: any NetworkReachabilityProviding
    ) {
        self.accountMonitor = accountMonitor
        self.networkMonitor = networkMonitor
    }

    /// Mark iCloud Drive as disabled for Lillist. The app probes this
    /// from `FileManager.default.ubiquityIdentityToken == nil` plus
    /// a follow-up settings-link offer; the classifier uses the
    /// stored bit on next `currentReason()`.
    public func setICloudDriveDisabled(_ value: Bool) {
        self.iCloudDriveDisabled = value
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
        if iCloudDriveDisabled { return .iCloudDriveDisabled }
        if await !networkMonitor.isReachable() { return .noNetwork }
        return nil
    }
}
