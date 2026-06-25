import AppIntents

/// Registers the user-facing App Intents with the system so they appear in
/// Shortcuts and Lock Screen widget configuration.
struct LillistShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                // `\(.applicationName)` resolves to "Lillist". These are
                // trigger-only: AppIntents only permits AppEntity/AppEnum
                // parameters *inline* in a phrase, never a free-text String,
                // so the spoken title is collected by the intent's
                // `requestValueDialog` ("What's the task?") rather than
                // embedded in the phrase.
                "Add to \(.applicationName)",
                "\(.applicationName) task"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: SearchTasksIntent(),
            phrases: [
                "Search \(.applicationName)"
            ],
            shortTitle: "Search Tasks",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: QuickCaptureLockScreenIntent(),
            phrases: [
                // Trigger-only (see AddTask note): the optional `text` is
                // supplied when the action is run from Shortcuts with input,
                // not embedded inline in a spoken phrase.
                "Quick capture in \(.applicationName)"
            ],
            shortTitle: "Quick Capture",
            systemImageName: "square.and.pencil"
        )
    }
}
