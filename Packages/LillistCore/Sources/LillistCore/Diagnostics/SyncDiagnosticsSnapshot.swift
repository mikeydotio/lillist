import Foundation
import Security

/// Which CloudKit environment (Development vs Production) this device's
/// signed build is talking to.
///
/// Issue #54: four devices on the same iCloud account diverged into separate
/// task islands because a distribution-channel split (a `/deployit` Ad-Hoc
/// iOS build / Developer-ID macOS build → Production; a local Xcode-run build
/// → Development) went undetected — the app had no runtime signal for its own
/// CloudKit environment, so a healthy-looking "sync is active" badge could sit
/// over a store mirroring to the wrong database. This type is that signal.
public enum CloudKitEnvironment: String, Codable, Sendable, Equatable {
    case development = "Development"
    case production = "Production"
    /// Neither the `icloud-container-environment` nor an `aps-environment`
    /// entitlement was present or recognized — e.g. the process is unsigned
    /// (`swift test`), or a future entitlement value this app doesn't know.
    case unknown = "unknown"
}

/// Seam over the running process's own code-signing entitlements, so
/// `SyncDiagnosticsSnapshot.resolveEnvironment` is unit-testable without a
/// signed binary. Production code uses `SelfEntitlementReader`; tests inject
/// a canned dictionary.
public protocol EntitlementReading: Sendable {
    func stringValue(forEntitlement key: String) -> String?
}

/// Reads the *running process's own* code-signing entitlements via the
/// public, App-Store-safe `Security` API `SecTaskCreateFromSelf` /
/// `SecTaskCopyValueForEntitlement` — the same mechanism apps use to
/// introspect their own provisioning at runtime. Returns `nil` for every key
/// when the process is unsigned (e.g. under `swift test`), which is why
/// production values are only ever read from inside the signed app.
public struct SelfEntitlementReader: EntitlementReading {
    public init() {}

    public func stringValue(forEntitlement key: String) -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        var error: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error)
        return value as? String
    }
}

/// A point-in-time capture of this device's CloudKit provenance: which
/// environment and container it's signed to talk to, its account and
/// sync-mode state, and the local/mirrored task counts.
///
/// Folded into `DiagnosticPackageBuilder.Metadata` (so an exported diagnostic
/// package reveals a Dev/Prod split without a Mac) and surfaced as a settings
/// row. Everything here is derived from cheap, already-available signals —
/// no new async plumbing beyond what the settings screens already fetch.
public struct SyncDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public let cloudKitEnvironment: CloudKitEnvironment
    public let cloudKitContainerIdentifier: String
    /// Human-readable label for the device's `iCloudAccountState` at capture
    /// time (`"available"`, `"noAccount"`, …). A `String`, not the enum
    /// itself, so this type doesn't need `CloudKit` in its `Codable` surface.
    public let accountStatusLabel: String
    public let syncMode: SyncMode
    /// From `TaskStore.SyncCounts` at capture time.
    public let mirroredCount: Int
    public let localCount: Int

    public init(
        cloudKitEnvironment: CloudKitEnvironment,
        cloudKitContainerIdentifier: String,
        accountStatusLabel: String,
        syncMode: SyncMode,
        mirroredCount: Int,
        localCount: Int
    ) {
        self.cloudKitEnvironment = cloudKitEnvironment
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.accountStatusLabel = accountStatusLabel
        self.syncMode = syncMode
        self.mirroredCount = mirroredCount
        self.localCount = localCount
    }
}

extension SyncDiagnosticsSnapshot {
    /// Present (hardcoded `Development`) on macOS; absent on iOS, where the
    /// environment is only implied by the APS-environment entitlement.
    static let iCloudEnvironmentEntitlementKey = "com.apple.developer.icloud-container-environment"
    /// iOS spelling of the push-environment entitlement.
    static let apsEnvironmentEntitlementKeyiOS = "aps-environment"
    /// macOS spelling of the same concept — prefixed, unlike iOS (see
    /// docs/engineering-notes.md "macOS push entitlement — FIXED", 2026-06-24).
    static let apsEnvironmentEntitlementKeymacOS = "com.apple.developer.aps-environment"

    /// Resolve this process's CloudKit environment from its own signed
    /// entitlements.
    ///
    /// Prefers the explicit iCloud-container-environment key; falls back to
    /// the APS-environment entitlement as a **proxy**, not a bug: per
    /// docs/engineering-notes.md, "CloudKit environment follows the
    /// distribution channel, not the build config" — a distribution export
    /// re-stamps both keys to Production in lockstep. iOS never embeds the
    /// iCloud key at all, so this fallback is the *only* runtime signal
    /// available there. Returns `.unknown` when neither key is present or
    /// recognized.
    public static func resolveEnvironment(using reader: EntitlementReading) -> CloudKitEnvironment {
        if let raw = reader.stringValue(forEntitlement: iCloudEnvironmentEntitlementKey) {
            return map(raw)
        }
        if let raw = reader.stringValue(forEntitlement: apsEnvironmentEntitlementKeyiOS)
            ?? reader.stringValue(forEntitlement: apsEnvironmentEntitlementKeymacOS) {
            return map(raw)
        }
        return .unknown
    }

    private static func map(_ raw: String) -> CloudKitEnvironment {
        switch raw.lowercased() {
        case "development": return .development
        case "production": return .production
        default: return .unknown
        }
    }

    /// Convenience assembly used by both app targets' diagnostics screens.
    /// Pure except for the (synchronous) entitlement read; callers gather the
    /// async pieces (`TaskStore.syncCounts()`, live account state) themselves
    /// and hand them in.
    public static func make(
        reader: EntitlementReading = SelfEntitlementReader(),
        containerIdentifier: String,
        accountState: iCloudAccountState,
        syncMode: SyncMode,
        counts: TaskStore.SyncCounts
    ) -> SyncDiagnosticsSnapshot {
        SyncDiagnosticsSnapshot(
            cloudKitEnvironment: resolveEnvironment(using: reader),
            cloudKitContainerIdentifier: containerIdentifier,
            accountStatusLabel: accountState.diagnosticLabel,
            syncMode: syncMode,
            mirroredCount: counts.mirrored,
            localCount: counts.local
        )
    }
}

extension iCloudAccountState {
    /// Stable, human-readable label for diagnostics (`manifest.json`, the
    /// in-app diagnostics row) — kept separate from `Codable` on the enum
    /// itself so `SyncDiagnosticsSnapshot` doesn't need to import `CloudKit`.
    public var diagnosticLabel: String {
        switch self {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .accountChanged: return "accountChanged"
        }
    }
}
