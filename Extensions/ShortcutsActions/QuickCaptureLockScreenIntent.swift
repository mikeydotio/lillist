import AppIntents

/// Discoverable entry point used by the Lock Screen widget. Opens the app
/// (which surfaces the Quick Capture sheet via `OpenAtQuickCaptureIntent`).
struct QuickCaptureLockScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Capture"
    static var description = IntentDescription("Capture a task into Lillist.")
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenAtQuickCaptureIntent())
    }
}

/// Hidden helper intent the main app handles on launch to present the
/// Quick Capture sheet immediately.
struct OpenAtQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Quick Capture"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}
