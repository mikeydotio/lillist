import Foundation

/// An opaque, comparable identity for the iCloud account currently signed
/// in on this device (data-sync-hardening `S3`).
///
/// Wraps `FileManager.ubiquityIdentityToken`'s archived representation —
/// see `AccountIdentityStore`'s type doc for why that API, not
/// `CKContainer.fetchUserRecordID`, is the identity source. The token
/// itself is a private Apple type that conforms only to `NSCoding`, not
/// `NSSecureCoding`, so equality is implemented by unarchiving both sides
/// with `requiresSecureCoding = false` and comparing via `isEqual` — the
/// comparison method Apple's own documentation specifies for this token,
/// not pointer or raw-byte equality.
public struct AccountIdentityToken: Sendable, Equatable {
    public let archivedData: Data

    public init(archivedData: Data) {
        self.archivedData = archivedData
    }

    /// Archives a live `ubiquityIdentityToken` value. Returns `nil` if
    /// archiving fails — treated by callers the same as "no current
    /// identity," since a token that can't even be archived can't be
    /// compared or persisted either.
    public init?(ubiquityToken: (NSCoding & NSCopying & NSObjectProtocol)?) {
        guard let ubiquityToken else { return nil }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: ubiquityToken, requiringSecureCoding: false) else {
            return nil
        }
        self.archivedData = data
    }

    public static func == (lhs: AccountIdentityToken, rhs: AccountIdentityToken) -> Bool {
        guard let l = Self.unarchive(lhs.archivedData), let r = Self.unarchive(rhs.archivedData) else {
            // Defensive fallback only — the primary path always unarchives
            // successfully for anything this type itself produced.
            return lhs.archivedData == rhs.archivedData
        }
        return l.isEqual(r)
    }

    private static func unarchive(_ data: Data) -> NSObject? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject
    }
}

/// Testable seam around "what iCloud account identity is current right
/// now." The production conformer wraps `FileManager.ubiquityIdentityToken`;
/// tests inject a controlled fake.
public protocol AccountIdentityProbing: Sendable {
    /// Returns the current identity token, or `nil` when no iCloud account
    /// is signed in on this device (or this app lacks iCloud Drive access —
    /// see `PauseReasonClassifier`'s reuse of this same seam for `S24`).
    func currentIdentity() -> AccountIdentityToken?
}

/// Production `AccountIdentityProbing` backed by
/// `FileManager.ubiquityIdentityToken` — synchronous, no network, and
/// (per Apple's own guidance) the documented way to detect an iCloud
/// account change without a CloudKit round trip.
public struct UbiquityIdentityProbe: AccountIdentityProbing {
    public init() {}
    public func currentIdentity() -> AccountIdentityToken? {
        AccountIdentityToken(ubiquityToken: FileManager.default.ubiquityIdentityToken)
    }
}

/// Durable storage for the last-known account identity. Implementations
/// must guarantee atomic writes, mirroring `ReseedJournalStore`'s
/// requirement — a crash between a write's temp-file creation and its
/// rename-install must never leave a half-written file for the next
/// launch to trip over.
public protocol AccountIdentityRecordStoring: Sendable {
    func readIdentity() throws -> AccountIdentityToken?
    func writeIdentity(_ token: AccountIdentityToken) throws
    func clear() throws
}

/// File-backed implementation, written with
/// `Data.write(to:options:.atomic)` — mirrors `FileReseedJournalStore`.
public struct FileAccountIdentityStore: AccountIdentityRecordStoring {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Build a store rooted at the App Group container's
    /// `Lillist/account-identity.json`. Returns `nil` if the App Group is
    /// not reachable.
    public init?(appGroupID: String) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        let dir = container.appendingPathComponent("Lillist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("account-identity.json")
    }

    public func readIdentity() throws -> AccountIdentityToken? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(Record.self, from: data)
        return AccountIdentityToken(archivedData: record.archivedTokenData)
    }

    public func writeIdentity(_ token: AccountIdentityToken) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let record = Record(archivedTokenData: token.archivedData, recordedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: url, options: [.atomic])
    }

    public func clear() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private struct Record: Codable {
        let archivedTokenData: Data
        let recordedAt: Date
    }
}

/// In-memory variant for unit tests and as the harmless default for
/// production callers that don't wire a durable store — mirrors
/// `InMemoryReseedJournalStore`.
public final class InMemoryAccountIdentityRecordStore: AccountIdentityRecordStoring, @unchecked Sendable {
    private var current: AccountIdentityToken?
    private let lock = NSLock()

    public init(initial: AccountIdentityToken? = nil) {
        self.current = initial
    }

    public func readIdentity() throws -> AccountIdentityToken? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func writeIdentity(_ token: AccountIdentityToken) throws {
        lock.lock()
        defer { lock.unlock() }
        current = token
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        current = nil
    }
}

/// Persists a stable identifier for "which iCloud account this device's
/// local store last belonged to," and detects when the currently
/// signed-in account differs (data-sync-hardening `S3`).
///
/// `check()` must run before `PersistenceController` arms
/// `cloudKitContainerOptions` — see the plan doc's launch-sequence diagram
/// (`docs/superpowers/plans/2026-07-28-plan-3a-account-identity-and-status.md`)
/// for exactly where `AppEnvironment.make()` calls this on both platforms.
/// A plain `struct`, not an actor: every method is synchronous (file I/O
/// only, no CloudKit calls), so no isolation is needed and callers can use
/// it from a `@MainActor` launch path without an `await`.
public struct AccountIdentityStore: Sendable {
    /// The outcome of comparing the current identity to the persisted one.
    public enum CheckResult: Sendable, Equatable {
        /// No identity was persisted yet — the current identity (if any)
        /// was adopted silently. Not a mismatch.
        case firstLaunch
        /// The persisted identity matches the current one.
        case match
        /// No iCloud account is currently signed in. NOT treated as a
        /// mismatch — callers should defer to the existing `.noAccount`
        /// pause path. The persisted identity is left untouched so a
        /// temporary sign-out doesn't forget which account this device
        /// belongs to.
        case mismatch
        /// The current identity differs from the persisted one.
        case signedOut
    }

    private let probe: any AccountIdentityProbing
    private let storage: any AccountIdentityRecordStoring

    public init(
        probe: any AccountIdentityProbing = UbiquityIdentityProbe(),
        storage: any AccountIdentityRecordStoring
    ) {
        self.probe = probe
        self.storage = storage
    }

    /// Compare the current identity against the persisted one. Mutates
    /// storage only to adopt on first launch (no persisted identity yet);
    /// a genuine mismatch is reported but never auto-resolved — see
    /// `adoptCurrentIdentity()`.
    public func check() throws -> CheckResult {
        let stored = try storage.readIdentity()
        let current = probe.currentIdentity()

        switch (stored, current) {
        case (nil, nil):
            return .firstLaunch
        case (nil, .some(let currentToken)):
            try storage.writeIdentity(currentToken)
            return .firstLaunch
        case (.some, nil):
            return .signedOut
        case (.some(let storedToken), .some(let currentToken)):
            return storedToken == currentToken ? .match : .mismatch
        }
    }

    /// Explicitly (re-)adopt the current identity as the persisted one —
    /// called by a mismatch-resolution flow only AFTER its chosen
    /// operation reports success (see the plan doc §3's council decision
    /// for why this ordering is binding).
    public func adoptCurrentIdentity() throws {
        guard let current = probe.currentIdentity() else {
            throw LillistError.storeUnavailable(reason: "No iCloud account is currently signed in; nothing to adopt.")
        }
        try storage.writeIdentity(current)
    }
}
