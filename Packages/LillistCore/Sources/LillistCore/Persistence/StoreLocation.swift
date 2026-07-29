import Foundation

/// The canonical, single-authority resolver for "where is the shared Core
/// Data store on disk" and "may this process arm CloudKit mirroring against
/// it" — the class-killer for data-sync-hardening findings `X1`, `X2`, and
/// `X15`.
///
/// Before this type existed, six processes each answered these two
/// questions independently, and at least three of those answers disagreed:
/// the macOS app used `StoreConfiguration.defaultOnDisk` (the sandbox
/// Application Support container) instead of the shared App Group (`X1`);
/// the `lillist` CLI built a third, different App-Group-relative path
/// (`X2`); and every non-app process (widget, Share extension, Shortcuts
/// extension, CLI) attached `cloudKitContainerOptions` whenever the
/// device's persisted `SyncMode` was `.iCloudSync`, regardless of whether
/// that process should be running its own CloudKit mirroring delegate at
/// all (`X15`).
///
/// `StoreLocation` fixes both by construction: every ``Role`` resolves to
/// the *identical* file URL for a given App Group container
/// (`<container>/Lillist/Lillist.sqlite`, matching the path iOS, the
/// widget, and both extensions already used correctly), and only
/// ``Role/mainApp`` may arm mirroring via ``makeConfiguration(syncMode:cloudKitContainerIdentifier:)``.
public struct StoreLocation: Sendable, Equatable {
    /// Which process is opening the shared store. Every case resolves to
    /// the same file path — the only thing that varies by role is whether
    /// CloudKit mirroring may be armed.
    public enum Role: String, Sendable, CaseIterable, Equatable {
        /// The iOS or macOS main app. The only role permitted to attach
        /// `cloudKitContainerOptions` — see ``mayArmCloudKitMirroring``.
        case mainApp
        /// The Share Extension or the Shortcuts (App Intents) Extension.
        case extensionProcess
        /// The iOS or macOS widget extension. Kept distinct from
        /// ``extensionProcess`` (rather than collapsed into one "non-main"
        /// role) because the codebase already distinguishes widget writes
        /// at the transaction-author level
        /// (`PersistenceController.widgetTransactionAuthor`), and the
        /// widget's cache-rebuild behavior (`X5`/`X6`, plan `5b`) may need
        /// to diverge from the Share/Shortcuts extensions later.
        case widget
        /// The `lillist` CLI.
        case cli

        /// Only `.mainApp` may attach `cloudKitContainerOptions` (`X15`).
        /// Every other role opens the shared store with persistent-history
        /// tracking and remote-change notifications still on (those are
        /// unconditional in `PersistenceController.makeStoreDescription`),
        /// but never arms its own CloudKit mirroring delegate against a
        /// file another process may already be mirroring.
        public var mayArmCloudKitMirroring: Bool {
            self == .mainApp
        }
    }

    /// The resolved on-disk URL of the shared `Lillist.sqlite` file.
    /// Identical across every ``Role`` for a given App Group container.
    public let url: URL
    /// The role this location was resolved for.
    public let role: Role

    /// Convenience mirror of `role.mayArmCloudKitMirroring`.
    public var mayArmCloudKitMirroring: Bool { role.mayArmCloudKitMirroring }

    /// The App Group shared by the iOS app, the macOS app, both widgets,
    /// both extensions, and the CLI. Matches the entitlement on every
    /// target.
    public static let defaultAppGroupIdentifier = "group.app.lillist"

    /// Resolve the canonical store location for a given role.
    ///
    /// - Parameters:
    ///   - role: which process is asking.
    ///   - appGroupID: the shared App Group identifier. Defaults to
    ///     ``defaultAppGroupIdentifier``.
    ///   - containerProvider: resolves the App Group's shared container
    ///     URL. Defaults to the real
    ///     `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
    ///     Tests inject a stand-in (e.g. a temp directory) — the real API
    ///     requires App Group entitlements no unsigned `swift test` process
    ///     has, and unsandboxed it appears to succeed for *any* group
    ///     identifier, making the "container unreachable" branch otherwise
    ///     untestable.
    ///   - fileManager: used to create the `Lillist` subdirectory. Defaults
    ///     to `.default`.
    /// - Throws: `LillistError.storeUnavailable` when the App Group
    ///   container is unreachable. Never falls back to a different path —
    ///   the whole point of this type is that there is exactly one path.
    public static func resolve(
        role: Role,
        appGroupID: String = defaultAppGroupIdentifier,
        containerProvider: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) },
        fileManager: FileManager = .default
    ) throws -> StoreLocation {
        guard let container = containerProvider(appGroupID) else {
            throw LillistError.storeUnavailable(reason: unavailableReason(for: role, appGroupID: appGroupID))
        }
        let dir = container.appendingPathComponent("Lillist", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Lillist.sqlite")
        return StoreLocation(url: url, role: role)
    }

    private init(url: URL, role: Role) {
        self.url = url
        self.role = role
    }

    private static func unavailableReason(for role: Role, appGroupID: String) -> String {
        switch role {
        case .cli:
            return "App group container '\(appGroupID)' is not available. Install the Lillist macOS app from the App Store or via Homebrew, then run it at least once."
        case .mainApp, .extensionProcess, .widget:
            return "App Group container '\(appGroupID)' is not available."
        }
    }

    /// Build a ready-to-use `StoreConfiguration` for this location:
    /// attaches the given `syncMode`, and suppresses CloudKit mirroring
    /// (`armsCloudKitMirroring = false`) unless `role.mayArmCloudKitMirroring`.
    public func makeConfiguration(
        syncMode: SyncMode,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier
    ) -> StoreConfiguration {
        StoreConfiguration(
            storeKind: .onDisk(url: url),
            cloudKitContainerIdentifier: cloudKitContainerIdentifier,
            syncMode: syncMode,
            armsCloudKitMirroring: mayArmCloudKitMirroring
        )
    }
}
