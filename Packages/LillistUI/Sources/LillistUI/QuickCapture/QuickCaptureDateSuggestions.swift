import Foundation

/// Canonical Quick Capture date-token chip list. Both the macOS
/// `QuickCaptureView` and the iOS `QuickCaptureSheet` render chips
/// from this list, so adding a token surfaces on both platforms
/// simultaneously.
///
/// Every token in `default` must round-trip through
/// `LillistCore.RelativeDate.parse(_:)`. Adding a token here without
/// extending the parser produces a chip the user can tap but the
/// parser can't resolve.
///
/// Localization note: Plan 17 Task 8 documents the parser-token
/// coupling. These tokens stay in English at the data layer; the
/// chip rendering can localize the *display* (e.g. show
/// "Today" in any locale) while the underlying parser token stays
/// `"today"`. That decoupling is a future plan — today the chip
/// label and the parser token are the same string.
public enum QuickCaptureDateSuggestions {
    public static let `default`: [String] = [
        "today",
        "tomorrow",
        "+3d",
        "+1w"
    ]
}
