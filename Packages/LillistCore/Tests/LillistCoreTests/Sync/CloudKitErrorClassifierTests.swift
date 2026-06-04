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
}
