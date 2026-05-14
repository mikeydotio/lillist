import AppIntents

/// Discoverable entry point used by the Lock Screen widget. Opens the app
/// (which surfaces the Quick Capture sheet via `OpenAtQuickCaptureIntent`).
struct QuickCaptureLockScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription("Capture a task into Lillist.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenAtQuickCaptureIntent())
    }
}

/// Hidden helper intent the main app handles on launch to present the
/// Quick Capture sheet immediately.
struct OpenAtQuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Capture"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}
