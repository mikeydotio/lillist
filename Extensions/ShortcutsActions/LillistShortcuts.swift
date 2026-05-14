import AppIntents

/// Registers the user-facing App Intents with the system so they appear in
/// Shortcuts and Lock Screen widget configuration.
struct LillistShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "New task in \(.applicationName)"
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
                "Quick capture in \(.applicationName)"
            ],
            shortTitle: "Quick Capture",
            systemImageName: "square.and.pencil"
        )
    }
}
