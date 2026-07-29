import Foundation
import CloudKit

/// Maps a raw CloudKit/`NSError` to the `LillistError` taxonomy so steady-state
/// sync failures get a typed, surfaceable posture instead of an opaque blob.
///
/// Review blind-spot persist-5: a `LillistError.quotaExceeded` case existed but
/// nothing populated it. The four codes singled out here are the ones a healthy
/// account actually hits in steady state:
///
/// - `.quotaExceeded`       → the user's iCloud storage is full (actionable).
/// - `.requestRateLimited`  → back off and retry (Core Data's mirror already
///                            honors the `CKErrorRetryAfterKey`; we surface it).
/// - `.serverRejectedRequest` / `.zoneBusy` → transient server-side conditions.
///
/// `.partialFailure` (`CKErrorDomain` code 2) is special-cased: a batch
/// operation where *some* records failed. Its top-level `localizedDescription`
/// is the useless "The operation couldn't be completed. (CKErrorDomain error
/// 2.)" — the actionable per-item reasons live in
/// `userInfo[CKPartialErrorsByItemIDKey]`. We unwrap that, tally the underlying
/// `CKError.Code`s, and surface a summary naming the dominant cause(s) and
/// count instead of the opaque blob.
///
/// Everything else collapses to `.syncFailure(underlying:)` carrying the
/// localized description, preserving today's behavior for unmodeled codes.
public enum CloudKitErrorClassifier {
    public static func classify(_ error: Error) -> LillistError {
        let ns = error as NSError
        guard ns.domain == CKErrorDomain, let code = CKError.Code(rawValue: ns.code) else {
            return .syncFailure(underlying: ns.localizedDescription)
        }
        switch code {
        case .quotaExceeded:
            return .quotaExceeded(resource: "iCloud")
        case .requestRateLimited:
            return .syncFailure(underlying: "CloudKit rate limited the request; will retry.")
        case .serverRejectedRequest:
            return .syncFailure(underlying: "CloudKit rejected the request.")
        case .zoneBusy:
            return .syncFailure(underlying: "CloudKit zone is busy; will retry.")
        case .zoneNotFound, .userDeletedZone:
            // S19: recoverable-with-context, not a permanent failure —
            // NSPersistentCloudKitContainer recreates its managed zone and
            // re-uploads through it on its own; distinguished from the
            // generic default-branch message so this specific,
            // self-healing condition doesn't read as an opaque failure.
            return .syncFailure(underlying: "iCloud's zone was deleted or is missing; it will be recreated automatically on the next sync.")
        case .partialFailure:
            return classifyPartialFailure(ns)
        default:
            return .syncFailure(underlying: ns.localizedDescription)
        }
    }

    /// Whether a sync failure is transient (the mirror retries + reconciles
    /// without user action) or structural (needs the user or a schema/account
    /// change). Drives whether `SyncStatusMonitor` latches a persistent red
    /// error: a single transient export conflict must NOT pin the badge.
    public enum Severity: Sendable, Equatable { case recoverable, structural }

    /// CloudKit codes `NSPersistentCloudKitContainer` recovers from on its own
    /// (network blips, conflicts it reconciles, rate-limit/back-off, busy zones).
    static let recoverableCodes: Set<CKError.Code> = [
        .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy,
        .requestRateLimited, .serverRecordChanged, .batchRequestFailed,
        .accountTemporarilyUnavailable,
        // S19: NSPersistentCloudKitContainer recreates a missing/deleted
        // managed zone and re-uploads through it on its own — a permanent
        // red badge here would misrepresent a condition the mirror already
        // self-heals from.
        .zoneNotFound, .userDeletedZone,
    ]

    /// Classify a sync error as transient vs structural.
    ///
    /// A `.partialFailure` is recoverable unless one of its per-item errors is a
    /// *structural* code. A **bare** partialFailure — no `CKPartialErrorsByItemIDKey`
    /// — is the mirror's ordinary "a record conflicted, reconciling" signal and is
    /// recoverable: a real diagnostic package showed imports of every record type
    /// succeeding (schema is fine) while a single non-recurring export
    /// partialFailure with no per-item dict latched the red badge permanently.
    /// Structural problems still surface as structural per-item codes or as
    /// non-partial top-level codes (quota / auth / rejected / invalidArguments).
    public static func severity(of error: Error) -> Severity {
        let ns = error as NSError
        guard ns.domain == CKErrorDomain, let code = CKError.Code(rawValue: ns.code) else {
            return .structural   // non-CloudKit → surface it
        }
        if code == .partialFailure {
            let partials = (ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError]) ?? [:]
            guard !partials.isEmpty else { return .recoverable }
            let allRecoverable = partials.values.allSatisfy {
                CKError.Code(rawValue: $0.code).map(recoverableCodes.contains) ?? false
            }
            return allRecoverable ? .recoverable : .structural
        }
        return recoverableCodes.contains(code) ? .recoverable : .structural
    }

    /// Summarize a `.partialFailure` from its per-item errors. Falls back to
    /// the top-level description when the partial-error dictionary is absent
    /// (some producers omit it) so we never lose the original message.
    private static func classifyPartialFailure(_ ns: NSError) -> LillistError {
        let partials = (ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError]) ?? [:]
        guard !partials.isEmpty else {
            return .syncFailure(underlying: ns.localizedDescription)
        }
        // Tally the underlying CloudKit codes, most-frequent first.
        var tally: [Int: Int] = [:]
        for itemError in partials.values {
            tally[itemError.code, default: 0] += 1
        }
        let summary = tally
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\(name(forCKCode: $0.key)): \($0.value)" }
            .joined(separator: ", ")
        let total = partials.count
        let noun = total == 1 ? "record" : "records"
        return .syncFailure(underlying: "\(total) \(noun) failed (\(summary))")
    }

    /// Human-readable name for a CloudKit error code, falling back to the raw
    /// value for codes outside the set a sync import/export realistically hits.
    static func name(forCKCode raw: Int) -> String {
        guard let code = CKError.Code(rawValue: raw) else { return "code \(raw)" }
        switch code {
        case .networkUnavailable: return "networkUnavailable"
        case .networkFailure: return "networkFailure"
        case .serviceUnavailable: return "serviceUnavailable"
        case .requestRateLimited: return "requestRateLimited"
        case .notAuthenticated: return "notAuthenticated"
        case .permissionFailure: return "permissionFailure"
        case .accountTemporarilyUnavailable: return "accountTemporarilyUnavailable"
        case .quotaExceeded: return "quotaExceeded"
        case .zoneNotFound: return "zoneNotFound"
        case .userDeletedZone: return "userDeletedZone"
        case .zoneBusy: return "zoneBusy"
        case .unknownItem: return "unknownItem"
        case .invalidArguments: return "invalidArguments"
        case .serverRecordChanged: return "serverRecordChanged"
        case .serverRejectedRequest: return "serverRejectedRequest"
        case .constraintViolation: return "constraintViolation"
        case .referenceViolation: return "referenceViolation"
        case .batchRequestFailed: return "batchRequestFailed"
        case .limitExceeded: return "limitExceeded"
        case .assetFileNotFound: return "assetFileNotFound"
        case .assetFileModified: return "assetFileModified"
        default: return "code \(raw)"
        }
    }
}
