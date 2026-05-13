import Testing
import Foundation
@testable import LillistCore

@Suite("LillistError")
struct LillistErrorTests {
    @Test("Errors are equatable for known cases")
    func equatable() {
        #expect(LillistError.notFound == LillistError.notFound)
        #expect(LillistError.notFound != LillistError.migrationRequired)
    }

    @Test("validationFailed carries issues")
    func validationFailedIssues() {
        let err = LillistError.validationFailed([
            .init(field: "title", message: "must not be empty")
        ])
        if case .validationFailed(let issues) = err {
            #expect(issues.count == 1)
            #expect(issues.first?.field == "title")
        } else {
            Issue.record("expected .validationFailed")
        }
    }

    @Test("ambiguous carries candidate IDs")
    func ambiguousCandidates() {
        let a = UUID()
        let b = UUID()
        let err = LillistError.ambiguous([a, b])
        if case .ambiguous(let ids) = err {
            #expect(ids == [a, b])
        } else {
            Issue.record("expected .ambiguous")
        }
    }

    @Test("Error has localized description for every case")
    func localizedDescriptions() {
        let cases: [LillistError] = [
            .storeUnavailable(reason: "test"),
            .iCloudUnavailable(reason: "test"),
            .syncFailure(underlying: "test"),
            .validationFailed([]),
            .notFound,
            .ambiguous([]),
            .quotaExceeded(resource: "test"),
            .attachmentTooLarge(byteSize: 0),
            .attachmentFetchFailed(url: URL(string: "https://example.com")!),
            .migrationRequired,
            .migrationFailed(underlying: "test")
        ]
        for err in cases {
            #expect(err.localizedDescription.isEmpty == false)
        }
    }
}
