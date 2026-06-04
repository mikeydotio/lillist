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
        default:
            return .syncFailure(underlying: ns.localizedDescription)
        }
    }
}
