import Foundation

/// Pure decision helper extracted from `ShareRootView.save()` so the
/// create-then-attach retry semantics can be unit-tested from the
/// standalone iOS test bundle (which can't `@testable import` the signed
/// share extension target).
///
/// The share sheet stays open after a failed link attachment so the user
/// can retry. On that retry the task already exists, so we must *not*
/// create a second one — we only re-attempt the attachment. This enum
/// encodes exactly that branch.
enum ShareSaveFlow {
    /// The next action `save()` should take.
    enum Step: Equatable {
        /// No task has been created yet — create one, and (when
        /// `attachLink` is true) attach the link afterwards.
        case createTask(attachLink: Bool)
        /// The task already exists (a prior attempt created it and then
        /// the link attachment failed) — skip creation and only attach.
        case attachLinkOnly(taskID: UUID)
    }

    /// Decide the next step given the task ID created by a prior attempt
    /// (`nil` if none yet) and whether the payload carries a URL.
    static func next(savedTaskID: UUID?, hasURL: Bool) -> Step {
        if let savedTaskID {
            return .attachLinkOnly(taskID: savedTaskID)
        }
        return .createTask(attachLink: hasURL)
    }
}
