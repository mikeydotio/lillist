import SwiftUI

/// Environment action that opens the unified task editor (the floating
/// `QuickCapturePanelController` panel) for a given task id. Injected by
/// `LillistApp` — which holds the `AppDelegate` and thus the panel — and
/// consumed by `TaskListView` (row click) and `RootSplitView` (Return).
///
/// A notification can't carry the panel reference and a row click already
/// knows its id, so a plain closure is the cleanest seam; the keyboard
/// "Open Task" command posts `.lillistOpenTaskEditor` and `RootSplitView`
/// resolves the selected id before calling this.
struct OpenTaskEditorActionKey: EnvironmentKey {
    static let defaultValue: @MainActor (UUID) -> Void = { _ in }
}

extension EnvironmentValues {
    var openTaskEditorAction: @MainActor (UUID) -> Void {
        get { self[OpenTaskEditorActionKey.self] }
        set { self[OpenTaskEditorActionKey.self] = newValue }
    }
}
