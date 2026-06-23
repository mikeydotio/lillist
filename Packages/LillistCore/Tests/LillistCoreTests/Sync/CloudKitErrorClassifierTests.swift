import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("CloudKitErrorClassifier")
struct CloudKitErrorClassifierTests {
    private func ckError(_ code: CKError.Code) -> NSError {
        NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: nil)
    }

    @Test("quotaExceeded maps to LillistError.quotaExceeded")
    func quota() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.quotaExceeded))
        #expect(mapped == .quotaExceeded(resource: "iCloud"))
    }

    @Test("requestRateLimited maps to a syncFailure mentioning rate limiting")
    func rateLimited() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.requestRateLimited))
        guard case let .syncFailure(underlying) = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
        #expect(underlying.localizedCaseInsensitiveContains("rate"))
    }

    @Test("serverRejectedRequest maps to a syncFailure")
    func serverRejected() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.serverRejectedRequest))
        guard case .syncFailure = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
    }

    @Test("zoneBusy maps to a syncFailure (transient/retryable)")
    func zoneBusy() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.zoneBusy))
        guard case .syncFailure = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
    }

    @Test("A non-CloudKit error falls back to syncFailure with its description")
    func nonCloudKit() {
        let raw = NSError(domain: "SomeOtherDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let mapped = CloudKitErrorClassifier.classify(raw)
        #expect(mapped == .syncFailure(underlying: "boom"))
    }

    // MARK: - partialFailure (CKErrorDomain error 2)

    private func partialFailure(_ items: [CKError.Code]) -> NSError {
        var byItemID: [AnyHashable: NSError] = [:]
        for (offset, code) in items.enumerated() {
            byItemID["item-\(offset)"] = NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: nil)
        }
        return NSError(
            domain: CKErrorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: byItemID]
        )
    }

    @Test("partialFailure with per-item errors summarizes the dominant code and count")
    func partialFailureSummarized() {
        let mapped = CloudKitErrorClassifier.classify(
            partialFailure([.zoneNotFound, .zoneNotFound, .serverRecordChanged])
        )
        guard case let .syncFailure(underlying) = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
        // 3 records total; zoneNotFound dominates (2) and is listed first.
        #expect(underlying.contains("3 records failed"))
        #expect(underlying.contains("zoneNotFound: 2"))
        #expect(underlying.contains("serverRecordChanged: 1"))
        let zoneIdx = underlying.range(of: "zoneNotFound")!.lowerBound
        let recIdx = underlying.range(of: "serverRecordChanged")!.lowerBound
        #expect(zoneIdx < recIdx, "more-frequent code should be listed first")
    }

    @Test("partialFailure with a single item uses the singular noun")
    func partialFailureSingular() {
        let mapped = CloudKitErrorClassifier.classify(partialFailure([.unknownItem]))
        guard case let .syncFailure(underlying) = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
        #expect(underlying.contains("1 record failed"))
        #expect(underlying.contains("unknownItem: 1"))
        #expect(!underlying.contains("records failed"))
    }

    @Test("partialFailure without a per-item dictionary falls back to the top-level description")
    func partialFailureNoDictionary() {
        let raw = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "top-level blob"]
        )
        let mapped = CloudKitErrorClassifier.classify(raw)
        #expect(mapped == .syncFailure(underlying: "top-level blob"))
    }

    @Test("name(forCKCode:) falls back to the raw value for unmodeled codes")
    func unmodeledCodeName() {
        // 9999 is not a real CKError.Code.
        #expect(CloudKitErrorClassifier.name(forCKCode: 9999) == "code 9999")
    }
}
