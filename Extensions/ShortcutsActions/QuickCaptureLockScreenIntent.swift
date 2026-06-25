import AppIntents
import LillistCore

/// Discoverable entry point used by the Lock Screen widget and Shortcuts.
/// Brings Lillist to the foreground (`openAppWhenRun`) and stashes the action's
/// input text via ``QuickCaptureHandoff``; the app drains the handoff when it
/// becomes active and opens the Quick Capture dialog pre-filled with that text.
/// Running with no text opens an empty dialog.
struct QuickCaptureLockScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription("Open Quick Capture in Lillist, optionally pre-filled.")
    static let openAppWhenRun = true

    @Parameter(title: "Text") var text: String?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Quick capture \(\.$text) in Lillist")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCaptureHandoff.stash(text ?? "", appGroupID: IntentSupport.appGroupID)
        return .result()
    }
}
