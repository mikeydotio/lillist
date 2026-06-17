import Foundation

/// The two presentations of the unified task editor. The modes differ
/// **only** in size and which sections are shown — everything else (the
/// hosting window/overlay, the backing `TaskEditorModel`, the singleton
/// rule) is identical between them.
///
/// - `quick`: a single title field, mirroring the historical Quick Capture
///   dialog. Used for fast new-task capture.
/// - `full`: every user-editable field inline. Reached by tapping/clicking
///   an existing task, or by fluidly expanding a `quick` capture via the
///   "…" affordance.
public enum TaskEditorMode: Sendable, Equatable {
    case quick
    case full
}

/// How the editor was opened — drives draft-vs-existing semantics.
///
/// - `capture`: a brand-new task. Starts as an in-memory draft (nothing in
///   Core Data) and commits explicitly or via silent auto-promote.
/// - `existing`: an already-persisted task. Edits live-save.
public enum TaskEditorPresentation: Sendable, Equatable {
    case capture
    case existing
}
