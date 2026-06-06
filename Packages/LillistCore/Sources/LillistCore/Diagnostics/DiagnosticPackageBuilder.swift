import Foundation

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
        public var files: [String]

        public init(buildVersion: String, osVersion: String, deviceModel: String, exportedAt: Date, diagnosticLoggingEnabled: Bool, files: [String] = []) {
            self.buildVersion = buildVersion
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.exportedAt = exportedAt
            self.diagnosticLoggingEnabled = diagnosticLoggingEnabled
            self.files = files
        }
    }

    public enum BuildError: Error, Equatable {
        case zipProducedNothing
    }

    let diagnosticsDir: URL?
    let storeURL: URL?
    let metadata: Metadata

    /// - Parameters:
    ///   - diagnosticsDir: App-Group `…/Lillist/Diagnostics` (nil → no logs).
    ///   - storeURL: the live store URL (nil for in-memory; store-include no-ops).
    ///   - metadata: build/OS/device + toggle state for the manifest.
    public init(diagnosticsDir: URL?, storeURL: URL?, metadata: Metadata) {
        self.diagnosticsDir = diagnosticsDir
        self.storeURL = storeURL
        self.metadata = metadata
    }

    /// Build the staging directory (no zip). Returns the staged
    /// `Lillist-Diagnostics` folder; the caller owns cleanup of its parent.
    /// Exposed so tests can inspect the manifest, merged events, and raw logs
    /// without unzipping (the `.forUploading` zip is one-way).
    public func stage(options: Options) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("DiagPackage-\(UUID().uuidString)", isDirectory: true)
        let stageDir = work.appendingPathComponent("Lillist-Diagnostics", isDirectory: true)
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

        // Task 14 inserts the consistent VACUUM INTO store snapshot here.

        var meta = metadata
        meta.files = inventory.sorted()
        try Self.manifestEncoder().encode(meta).write(to: stageDir.appendingPathComponent("manifest.json"))

        return stageDir
    }

    /// Stage, zip, and return a temp `.zip` URL. Cleans up the staging directory.
    public func build(options: Options) async throws -> URL {
        let fm = FileManager.default
        let stageDir = try stage(options: options)
        defer { try? fm.removeItem(at: stageDir.deletingLastPathComponent()) }
        return try Self.zip(directory: stageDir)
    }

    /// Decode every `diag-*.jsonl` file and return all events sorted by `at`
    /// then `seq` — the canonical merged timeline.
    public static func mergeEvents(from files: [URL]) -> [DiagnosticEvent] {
        var all: [DiagnosticEvent] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let events = try? DiagnosticEvent.decodeJSONLines(text)
            else { continue }
            all.append(contentsOf: events)
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
