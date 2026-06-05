import XCTest
import Foundation

/// Unit tests for `ShareSaveFlow`, the pure decision helper extracted from
/// `ShareRootView.save()`. `ShareSaveFlow` is co-compiled into this
/// standalone test bundle (see project.yml) because the share extension
/// target can't be `@testable import`-ed without a signed app host.
///
/// The behavior under test: when the link attachment fails, the already-
/// created task must NOT be re-created on the user's retry — the flow must
/// reuse the saved task ID and attempt only the attachment.
final class ShareSaveFlowTests: XCTestCase {
    func test_firstSave_createsTaskAndRequestsAttachment_whenURLPresent() {
        let step = ShareSaveFlow.next(savedTaskID: nil, hasURL: true)
        switch step {
        case .createTask(attachLink: let attach):
            XCTAssertTrue(attach, "A first save with a URL must request the link attachment")
        case .attachLinkOnly:
            XCTFail("First save must create the task, not skip to attach-only")
        }
    }

    func test_firstSave_createsTaskWithoutAttachment_whenNoURL() {
        let step = ShareSaveFlow.next(savedTaskID: nil, hasURL: false)
        switch step {
        case .createTask(attachLink: let attach):
            XCTAssertFalse(attach, "A first save with no URL must not request an attachment")
        case .attachLinkOnly:
            XCTFail("First save must create the task, not skip to attach-only")
        }
    }

    func test_retryAfterAttachmentFailure_reusesSavedTask_doesNotCreateAgain() {
        let saved = UUID()
        let step = ShareSaveFlow.next(savedTaskID: saved, hasURL: true)
        switch step {
        case .createTask:
            XCTFail("Retry must NOT create a second task — the first one already exists")
        case .attachLinkOnly(taskID: let id):
            XCTAssertEqual(id, saved, "Retry must reuse the already-saved task ID")
        }
    }
}
