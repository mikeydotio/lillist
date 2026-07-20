import Foundation
import SQLite3

/// Assembles the diagnostic export `.zip`: merged + raw JSONL logs, a manifest,
/// and (Task 14) a consistent SQLite store snapshot. Mirrors `Exporter`'s
/// stage-then-write discipline — everything is built into a temp staging
/// directory, then zipped via `NSFileCoordinator(.forUploading)` (no SPM zip
/// dependency). The produced zip is copied out of the coordinator's transient
/// location before the accessor block returns.
public struct DiagnosticPackageBuilder: Sendable {
    public struct Options: Sendable {
        public var includeLogs: Bool
        public var includeStore: Bool
        public init(includeLogs: Bool, includeStore: Bool) {
            self.includeLogs = includeLogs
            self.includeStore = includeStore
        }
    }

    /// Written to `manifest.json`. `files` is the inventory, filled during staging.
    public struct Metadata: Codable, Sendable {
        public let buildVersion: String
        public let osVersion: String
        public let deviceModel: String
        public let exportedAt: Date
        public let diagnosticLoggingEnabled: Bool
        /// Issue #54: this device's CloudKit provenance (environment,
        /// container, account, sync mode, mirror counts) at export time — the
        /// signal that reveals a Dev/Prod distribution-channel split across a
        /// fleet without a Mac. `nil` for packages built before this field
        /// existed or where the caller couldn't assemble it.
        public var sync: SyncDiagnosticsSnapshot?
        public var files: [String]
        public var notes: [String]

        public init(buildVersion: String, osVersion: String, deviceModel: String, exportedAt: Date, diagnosticLoggingEnabled: Bool, sync: SyncDiagnosticsSnapshot? = nil, files: [String] = [], notes: [String] = []) {
            self.buildVersion = buildVersion
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.exportedAt = exportedAt
            self.diagnosticLoggingEnabled = diagnosticLoggingEnabled
            self.sync = sync
            self.files = files
            self.notes = notes
        }
    }

    public enum BuildError: Error, Equatable {
        case zipProducedNothing
        case snapshotFailed(message: String)
    }

    let diagnosticsDir: URL?
    let storeURL: URL?
    let metadata: Metadata
    /// Source for the process's recent unified-log (`os_log`) lines, captured
    /// into `unified-log.txt`. This is how CloudKit sync errors — which are
    /// logged to `LillistLog` (subsystem `CrashReporting.subsystemIdentifier`)
    /// but never to the file-based `DiagnosticLog` — reach the package. A `nil`
    /// fetcher or a failed/empty fetch simply omits the file. Injectable so
    /// tests can supply a fake instead of touching `OSLogStore`.
    let logFetcher: LogFetching?

    /// - Parameters:
    ///   - diagnosticsDir: App-Group `…/Lillist/Diagnostics` (nil → no logs).
    ///   - storeURL: the live store URL (nil for in-memory; store-include no-ops).
    ///   - metadata: build/OS/device + toggle state for the manifest.
    ///   - logFetcher: unified-log source (defaults to the live `OSLogFetcher`).
    public init(diagnosticsDir: URL?, storeURL: URL?, metadata: Metadata, logFetcher: LogFetching? = OSLogFetcher()) {
        self.diagnosticsDir = diagnosticsDir
        self.storeURL = storeURL
        self.metadata = metadata
        self.logFetcher = logFetcher
    }

    /// Build the staging directory (no zip). Returns the staged
    /// `Lillist-Diagnostics` folder; the caller owns cleanup of its parent.
    /// Exposed so tests can inspect the manifest, merged events, and raw logs
    /// without unzipping (the `.forUploading` zip is one-way).
    public func stage(options: Options, unifiedLog: [String] = []) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("DiagPackage-\(UUID().uuidString)", isDirectory: true)
        let stageDir = work.appendingPathComponent("Lillist-Diagnostics", isDirectory: true)
        // Clean up the work dir if staging throws (e.g. the store snapshot fails);
        // on success the caller (build, or a test) owns the returned dir's parent.
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: work) } }
        try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)

        var inventory: [String] = []

        if options.includeLogs, let diagnosticsDir {
            let dayFiles = ((try? fm.contentsOfDirectory(at: diagnosticsDir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("diag-") && $0.pathExtension == "jsonl" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            let rawDir = stageDir.appendingPathComponent("raw", isDirectory: true)
            try fm.createDirectory(at: rawDir, withIntermediateDirectories: true)
            for file in dayFiles {
                let dest = rawDir.appendingPathComponent(file.lastPathComponent)
                try? fm.copyItem(at: file, to: dest)
                inventory.append("raw/\(file.lastPathComponent)")
            }

            // Merged, time-ordered view across all per-process files.
            let merged = Self.mergeEvents(from: dayFiles)
            let mergedText = merged.compactMap { try? DiagnosticEvent.encodeJSONLine($0) }.joined()
            try Data(mergedText.utf8).write(to: stageDir.appendingPathComponent("events.jsonl"))
            inventory.append("events.jsonl")
        }

        if options.includeLogs, !unifiedLog.isEmpty {
            // Recent unified-log (`os_log`) lines — the only place CloudKit sync
            // errors surface, since `LillistLog` writes them to the unified log
            // and not to the file-based `DiagnosticLog` above. Already redacted
            // by the caller (`build`).
            let text = unifiedLog.joined(separator: "\n") + "\n"
            try Data(text.utf8).write(to: stageDir.appendingPathComponent("unified-log.txt"))
            inventory.append("unified-log.txt")
        }

        var notes: [String] = []
        if options.includeStore {
            if let storeURL {
                // A snapshot failure must NOT abort the whole package — degrade to
                // logs-only with a manifest note (design §8). The user still gets
                // the logs, which are usually the more useful half.
                do {
                    let storeDir = stageDir.appendingPathComponent("store", isDirectory: true)
                    try fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
                    let dest = storeDir.appendingPathComponent("Lillist.sqlite")
                    try Self.snapshotStore(at: storeURL, into: dest)
                    inventory.append("store/Lillist.sqlite")
                } catch {
                    try? fm.removeItem(at: stageDir.appendingPathComponent("store", isDirectory: true))
                    notes.append("store snapshot failed (\(error.localizedDescription)); package contains logs only")
                }
            } else {
                // In-memory (/dev/null) stores have no URL to snapshot.
                notes.append("store snapshot skipped: no on-disk store URL")
            }
        }

        var meta = metadata
        meta.files = inventory.sorted()
        meta.notes = notes
        try Self.manifestEncoder().encode(meta).write(to: stageDir.appendingPathComponent("manifest.json"))

        succeeded = true
        return stageDir
    }

    /// Produce one consistent SQLite file from the live store using
    /// `VACUUM INTO`. Opens the source **read-only** (the live store can't be
    /// closed) and writes a fresh, fully-checkpointed copy — no need to copy the
    /// `-wal`/`-shm` sidecars, and no torn read. `dest` must not already exist.
    static func snapshotStore(at storeURL: URL, into dest: URL) throws {
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        guard openResult == SQLITE_OK else {
            throw BuildError.snapshotFailed(message: "open: \(String(cString: sqlite3_errmsg(db)))")
        }
        let escaped = dest.path.replacingOccurrences(of: "'", with: "''")
        var errmsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, "VACUUM INTO '\(escaped)'", nil, nil, &errmsg)
        guard rc == SQLITE_OK else {
            let message = errmsg.map { String(cString: $0) } ?? "rc=\(rc)"
            sqlite3_free(errmsg)
            throw BuildError.snapshotFailed(message: "vacuum: \(message)")
        }
    }

    /// Stage, zip, and return a temp `.zip` URL. Cleans up the staging directory.
    public func build(options: Options) async throws -> URL {
        let fm = FileManager.default
        let unifiedLog = options.includeLogs ? await fetchUnifiedLog() : []
        let stageDir = try stage(options: options, unifiedLog: unifiedLog)
        defer { try? fm.removeItem(at: stageDir.deletingLastPathComponent()) }
        return try Self.zip(directory: stageDir)
    }

    /// Fetch + redact the process's recent unified-log lines for the app's
    /// subsystem. Best-effort: a missing fetcher or an `OSLogStore` failure
    /// (e.g. sandboxed tests, no entitlement) yields no lines rather than
    /// aborting the whole package. `OSLogStore(scope: .currentProcessIdentifier)`
    /// is bounded by this process's launch, so the window is a generous upper
    /// bound, not a guarantee of two hours of history.
    private func fetchUnifiedLog() async -> [String] {
        guard let logFetcher else { return [] }
        let since = Date(timeIntervalSinceNow: -7200)
        let raw = (try? await logFetcher.fetchRecentLines(
            since: since,
            subsystem: CrashReporting.subsystemIdentifier
        )) ?? []
        return raw.map(LogRedactor.redact)
    }

    /// Decode every `diag-*.jsonl` file and return all events sorted by `at`
    /// then `seq` — the canonical merged timeline.
    ///
    /// Decoding is **per line**: a single torn/corrupt line (e.g. a process
    /// killed mid-write) skips only that line, never the whole file's day — the
    /// merged timeline must stay resilient. The raw files travel in the package
    /// too, so a skipped line is still recoverable.
    public static func mergeEvents(from files: [URL]) -> [DiagnosticEvent] {
        var all: [DiagnosticEvent] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let event = try? DiagnosticEvent.decodeJSONLine(String(line)) {
                    all.append(event)
                }
            }
        }
        return all.sorted { ($0.at, $0.seq) < ($1.at, $1.seq) }
    }

    static func manifestEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Zip `directory` via `NSFileCoordinator(.forUploading)`. The coordinator
    /// hands us a transient `.zip`; we copy it to a stable temp URL before the
    /// accessor block returns (the transient one is reclaimed afterward).
    static func zip(directory: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var produced: URL?
        var copyError: Error?
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lillist-Diagnostics-\(UUID().uuidString).zip")

        coordinator.coordinate(readingItemAt: directory, options: [.forUploading], error: &coordinationError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: dest)
                produced = dest
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard let produced else { throw BuildError.zipProducedNothing }
        return produced
    }
}
