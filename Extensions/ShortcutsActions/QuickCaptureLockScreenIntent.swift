import AppIntents

/// Discoverable entry point used by the Lock Screen widget and Shortcuts.
/// Brings Lillist to the foreground (`openAppWhenRun`); the app has no
/// AppIntents surface to auto-present the Quick Capture sheet, so this
/// intent's effect today is simply to open the app.
struct QuickCaptureLockScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription("Capture a task into Lillist.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
