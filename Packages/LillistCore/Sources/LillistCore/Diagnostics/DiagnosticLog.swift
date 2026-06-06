import Foundation

/// Append-only, fire-and-forget JSONL writer for diagnostic events.
///
/// Mirrors `BreadcrumbBuffer`'s actor discipline (thread-safe, never throws into
/// callers) but, unlike the in-memory breadcrumb ring, persists to disk: one file
/// per process per day at `<directory>/diag-<yyyy-MM-dd>-<process>.jsonl`. The
/// `enabled` flag is a **cached Bool** (set at construction, mutated via
/// `setEnabled`) so `log` never has to `await` the `DevicePreferencesStore` actor
/// on the hot path. I/O failures are swallowed and counted in `dropped`; logging
/// can never affect a drag, save, or any caller.
public actor DiagnosticLog {
    private let directory: URL?
    private let process: DiagProcess
    private var enabled: Bool
    private let fixedDayStamp: String?
    private let retentionDays: Int

    private var dropped: Int = 0
    private var handle: FileHandle?
    private var openDayStamp: String?
    private var didPrune = false
    private var nextSeq: UInt64 = 0

    /// Test/explicit initializer. `dayStamp` pins the file's day for deterministic
    /// tests; in production it is `nil` and each event's `at` drives the day.
    public init(directory: URL?, process: DiagProcess, enabled: Bool, dayStamp: String? = nil, retentionDays: Int = 30) {
        self.directory = directory
        self.process = process
        self.enabled = enabled
        self.fixedDayStamp = dayStamp
        self.retentionDays = retentionDays
    }

    // MARK: App-Group factory

    /// Per-process singleton resolving the on-disk diagnostics directory:
    /// App-Group `…/Lillist/Diagnostics`, falling back to Application Support
    /// `…/Lillist/Diagnostics`, else `nil` (logging becomes a silent no-op).
    /// The first caller's `enabled` seeds the instance; later callers update it
    /// via `setEnabled` once they've read `DevicePreferencesStore`. App Intents
    /// caches its controller per process, so the same process can request twice —
    /// the registry returns the same actor each time.
    public static func shared(process: DiagProcess, appGroupID: String, enabled: Bool) -> DiagnosticLog {
        SharedRegistry.shared.log(for: process) {
            DiagnosticLog(directory: resolveDirectory(appGroupID: appGroupID), process: process, enabled: enabled)
        }
    }

    static func resolveDirectory(appGroupID: String) -> URL? {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group.appendingPathComponent("Lillist/Diagnostics", isDirectory: true)
        }
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            return appSupport.appendingPathComponent("Lillist/Diagnostics", isDirectory: true)
        }
        return nil
    }

    public func setEnabled(_ value: Bool) { enabled = value }
    public func droppedCount() -> Int { dropped }

    /// Append one event as a JSONL line. Fire-and-forget: returns immediately on
    /// any failure after incrementing `dropped`.
    public func log(_ event: DiagnosticEvent) {
        guard enabled, let directory else { return }
        pruneOnceIfNeeded(in: directory, now: event.at)
        // The log owns the authoritative `process` (only it knows the true
        // writing process) and the per-file monotonic `seq` (so events from all
        // emitters — observer, stores, drag — share one ordering). Emitters pass
        // placeholders for both; they are overwritten here.
        let stamped = DiagnosticEvent(
            at: event.at,
            seq: nextSeq,
            process: process,
            category: event.category,
            name: event.name,
            payload: event.payload
        )
        nextSeq += 1
        do {
            let stamp = fixedDayStamp ?? Self.utcDayStamp(stamped.at)
            let handle = try fileHandle(for: stamp, in: directory)
            let line = try DiagnosticEvent.encodeJSONLine(stamped)
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            dropped += 1
        }
    }

    private func fileHandle(for stamp: String, in dir: URL) throws -> FileHandle {
        if let handle, openDayStamp == stamp { return handle }   // same day → reuse
        try? handle?.close()                                     // day rollover → close + reopen
        handle = nil
        openDayStamp = nil
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("diag-\(stamp)-\(process.rawValue).jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        handle = h
        openDayStamp = stamp
        return h
    }

    private func pruneOnceIfNeeded(in dir: URL, now: Date) {
        guard !didPrune else { return }
        didPrune = true
        pruneOldFiles(olderThanDays: retentionDays, now: now)
    }

    /// Delete `diag-*.jsonl` files whose day stamp is more than `days` before
    /// `now`. Run once per process (first `log`); also callable directly in tests.
    public func pruneOldFiles(olderThanDays days: Int, now: Date) {
        guard let directory else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: now) ?? now
        let cutoffStamp = Self.utcDayStamp(cutoff)
        for f in files where f.lastPathComponent.hasPrefix("diag-") && f.pathExtension == "jsonl" {
            // diag-<yyyy>-<MM>-<dd>-<process>.jsonl — process names never contain "-".
            let parts = f.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard parts.count >= 4 else { continue }
            let stamp = "\(parts[1])-\(parts[2])-\(parts[3])"
            // Lexical comparison is valid for zero-padded yyyy-MM-dd stamps.
            if stamp < cutoffStamp { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// Lock-guarded per-process cache backing `shared`. `shared` is synchronous
    /// (callers want a non-`await` handle), so the cache can't be an actor; a
    /// lock-protected dictionary keeps it Sendable-safe under strict concurrency.
    private final class SharedRegistry: @unchecked Sendable {
        static let shared = SharedRegistry()
        private let lock = NSLock()
        private var logs: [DiagProcess: DiagnosticLog] = [:]
        func log(for process: DiagProcess, make: () -> DiagnosticLog) -> DiagnosticLog {
            lock.lock(); defer { lock.unlock() }
            if let existing = logs[process] { return existing }
            let created = make()
            logs[process] = created
            return created
        }
    }

    static func utcDayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
