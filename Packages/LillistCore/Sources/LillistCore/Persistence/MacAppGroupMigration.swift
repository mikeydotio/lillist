import Foundation

/// One-time migration of the macOS app's pre-App-Group Application Support
/// store into the shared App Group container (data-sync-hardening `X1`).
///
/// Runs **before** any `PersistenceController` opens either candidate
/// file — a pure file-system operation on two closed stores. macOS's
/// `AppEnvironment.make()` calls this ahead of constructing its
/// `PersistenceController`, so neither file has an active
/// `NSPersistentStoreCoordinator` at this point; there is nothing to race.
///
/// Every "copy" step stages through `QuarantineManager.copyStore(at:label:)`
/// (already-tested disk-space preflight + `.sqlite`/`-wal`/`-shm` copy)
/// into quarantine **before** either live store is touched, and the staged
/// copy is verified (byte-size match against the source) before anything
/// is moved into place. A failure at any point before the final
/// placement/quarantine steps leaves **both** original stores completely
/// untouched and safely retryable on the next launch — placement itself
/// (a same-directory `moveItem`, run only after verification) is treated
/// as exceptional and throws loud rather than degrading to
/// `.migrationFailed`, since a verified copy failing to *move* a few
/// directory entries indicates a corrupted environment, not a routine,
/// recoverable condition like low disk space.
public enum MacAppGroupMigration {
    /// A forensic snapshot of one candidate store's on-disk footprint,
    /// captured without opening Core Data. Attached to the conflict
    /// outcomes so a log/crash-report surface is actionable, not a bare
    /// enum case (binding requirement from the plan's council-vote
    /// deliberation).
    public struct StoreFootprint: Sendable, Equatable {
        public let url: URL
        public let sizeBytes: Int64
        public let modificationDate: Date?

        public init(url: URL, sizeBytes: Int64, modificationDate: Date?) {
            self.url = url
            self.sizeBytes = sizeBytes
            self.modificationDate = modificationDate
        }
    }

    public enum Outcome: Sendable, Equatable {
        /// No legacy store file — fresh install, or already migrated on a
        /// prior launch (the legacy original was quarantined away then).
        case notNeeded
        /// The App-Group location was empty; the legacy store was copied
        /// into it and the legacy original quarantined (moved, never
        /// deleted).
        case migrated(quarantinedLegacyAt: URL)
        /// Both stores existed and the device is in `.iCloudSync` mode
        /// (council decision): the pre-existing App-Group store was
        /// quarantined, the legacy store copied into its place, and the
        /// legacy original then also quarantined.
        case migratedResolvingConflict(
            quarantinedAppGroupAt: URL,
            quarantinedLegacyAt: URL,
            legacy: StoreFootprint,
            appGroup: StoreFootprint
        )
        /// Both stores existed and the device is in `.localOnly` mode
        /// (council decision): **no file was touched**. In this mode the
        /// App-Group store has no CloudKit mirror at all, so quarantining
        /// it would be unconditional, permanent loss of a real user
        /// action (e.g. a task completed via the widget). The app keeps
        /// booting on the legacy store this launch.
        case conflictDetected(legacy: StoreFootprint, appGroup: StoreFootprint)
        /// The staged copy or its verification failed (disk space, I/O).
        /// Neither store was touched; the caller should fall back to the
        /// legacy store for this launch — the migration retries
        /// automatically on the next one.
        case migrationFailed(reason: String)
    }

    /// Run the migration.
    ///
    /// - Parameters:
    ///   - legacyURL: the pre-App-Group sandbox store location
    ///     (`StoreConfiguration.defaultOnDisk`'s URL).
    ///   - groupURL: the canonical App-Group store location
    ///     (`StoreLocation.resolve(role: .mainApp).url`).
    ///   - syncMode: the device's persisted `SyncMode`, read before any
    ///     file is touched — governs the both-stores-populated policy.
    ///   - quarantine: the `QuarantineManager` rooted at the App-Group
    ///     `Lillist` directory (the same root the rest of the app's
    ///     quarantine/backup subsystems use).
    ///   - fileManager: used for existence/attribute/move operations.
    ///     Defaults to `.default`.
    public static func migrateIfNeeded(
        legacyURL: URL,
        groupURL: URL,
        syncMode: SyncMode,
        quarantine: QuarantineManager,
        fileManager: FileManager = .default
    ) throws -> Outcome {
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return .notNeeded
        }
        guard fileManager.fileExists(atPath: groupURL.path) else {
            return try performSimpleMigration(
                legacyURL: legacyURL, groupURL: groupURL, quarantine: quarantine, fileManager: fileManager
            )
        }

        // Both stores exist — capture forensic footprints of the
        // PRE-migration state before either branch below can touch them.
        let legacyFootprint = try footprint(of: legacyURL, fileManager: fileManager)
        let appGroupFootprint = try footprint(of: groupURL, fileManager: fileManager)

        switch syncMode {
        case .localOnly:
            return .conflictDetected(legacy: legacyFootprint, appGroup: appGroupFootprint)
        case .iCloudSync:
            return try performConflictMigration(
                legacyURL: legacyURL,
                groupURL: groupURL,
                legacyFootprint: legacyFootprint,
                appGroupFootprint: appGroupFootprint,
                quarantine: quarantine,
                fileManager: fileManager
            )
        }
    }

    /// The result of attempting to stage a verified copy: either the
    /// staged main-file URL, ready to place, or the outcome to return
    /// immediately (`.migrationFailed(reason:)`).
    private enum StagingResult {
        case staged(URL)
        case failed(Outcome)
    }

    private static func performSimpleMigration(
        legacyURL: URL,
        groupURL: URL,
        quarantine: QuarantineManager,
        fileManager: FileManager
    ) throws -> Outcome {
        switch try stageVerifiedCopy(of: legacyURL, quarantine: quarantine, fileManager: fileManager) {
        case .failed(let outcome):
            return outcome
        case .staged(let staged):
            try placeStagedCopy(staged, at: groupURL, fileManager: fileManager)
            let quarantinedLegacy = try quarantine.quarantineStore(at: legacyURL, label: "macos-migration-legacy")
            return .migrated(quarantinedLegacyAt: quarantinedLegacy)
        }
    }

    private static func performConflictMigration(
        legacyURL: URL,
        groupURL: URL,
        legacyFootprint: StoreFootprint,
        appGroupFootprint: StoreFootprint,
        quarantine: QuarantineManager,
        fileManager: FileManager
    ) throws -> Outcome {
        switch try stageVerifiedCopy(of: legacyURL, quarantine: quarantine, fileManager: fileManager) {
        case .failed(let outcome):
            return outcome
        case .staged(let staged):
            // Verified — now touch the live stores. Quarantine the
            // existing App-Group store FIRST, freeing the target path for
            // the staged copy (moveItem/copyItem both throw on an
            // existing destination).
            let quarantinedAppGroup = try quarantine.quarantineStore(at: groupURL, label: "macos-migration-app-group-conflict")
            try placeStagedCopy(staged, at: groupURL, fileManager: fileManager)
            let quarantinedLegacy = try quarantine.quarantineStore(at: legacyURL, label: "macos-migration-legacy")
            return .migratedResolvingConflict(
                quarantinedAppGroupAt: quarantinedAppGroup,
                quarantinedLegacyAt: quarantinedLegacy,
                legacy: legacyFootprint,
                appGroup: appGroupFootprint
            )
        }
    }

    /// Stage a verified copy of `source` via `QuarantineManager.copyStore`.
    private static func stageVerifiedCopy(
        of source: URL,
        quarantine: QuarantineManager,
        fileManager: FileManager
    ) throws -> StagingResult {
        let staged: QuarantineManager.QuarantinedBackup
        do {
            staged = try quarantine.copyStore(at: source, label: "macos-migration-staging")
        } catch {
            return .failed(.migrationFailed(reason: "Could not stage a copy of the legacy store: \(error.localizedDescription)"))
        }
        do {
            try verifyStagedCopy(source: source, staged: staged.storeURL, fileManager: fileManager)
        } catch {
            return .failed(.migrationFailed(reason: "Staged copy of the legacy store did not verify: \(error.localizedDescription)"))
        }
        return .staged(staged.storeURL)
    }

    /// Move a verified staged copy (and its sidecars, if present) into
    /// its final location, then best-effort clean up the now-empty
    /// staging directory. `destination`'s parent directory is guaranteed
    /// to exist (`StoreLocation.resolve` creates it); the destination
    /// path itself must not already have a file at it — callers are
    /// responsible for quarantining any pre-existing store there first.
    private static func placeStagedCopy(_ stagedMainFile: URL, at destination: URL, fileManager: FileManager) throws {
        try fileManager.moveItem(at: stagedMainFile, to: destination)
        for ext in ["wal", "shm"] {
            let sidecar = stagedMainFile.appendingPathExtension(ext)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            try fileManager.moveItem(at: sidecar, to: destination.appendingPathExtension(ext))
        }
        // Best-effort tidy-up: the staging directory is empty now that
        // its file(s) were moved out. Not safety-critical — a leftover
        // empty directory is harmless and would eventually be swept by
        // QuarantineManager.cleanupExpired() anyway.
        try? fileManager.removeItem(at: stagedMainFile.deletingLastPathComponent())
    }

    /// Defense-in-depth: compares the staged copy's main-file byte size
    /// against the source's. `QuarantineManager.copyStore` already throws
    /// on most I/O failures via `copyItem`; this catches silent truncation
    /// a successful-but-incomplete copy could theoretically produce.
    /// `internal` (not `private`) so tests can drive it directly.
    static func verifyStagedCopy(source: URL, staged: URL, fileManager: FileManager) throws {
        let sourceSize = try size(ofItemAt: source, fileManager: fileManager)
        let stagedSize = try size(ofItemAt: staged, fileManager: fileManager)
        guard sourceSize == stagedSize else {
            throw LillistError.storeUnavailable(
                reason: "size mismatch: source \(sourceSize) bytes, staged copy \(stagedSize) bytes"
            )
        }
    }

    /// Build a `StoreFootprint` for a store file without opening Core
    /// Data. `internal` (not `private`) so tests can drive it directly.
    static func footprint(of url: URL, fileManager: FileManager) throws -> StoreFootprint {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = attrs[.modificationDate] as? Date
        return StoreFootprint(url: url, sizeBytes: size, modificationDate: mtime)
    }

    private static func size(ofItemAt url: URL, fileManager: FileManager) throws -> Int64 {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? -1
    }
}
