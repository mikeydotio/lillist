import Foundation

/// Canonical Quick Capture date-token chip list. The macOS
/// `QuickCaptureView` renders chips from this list.
///
/// The iOS surface stopped rendering these chips in Plan 22 (the
/// Spotlight-style dialog redesign): the streamlined empty state has
/// no suggestion row, only a dim footer legend teaching the `#tag` /
/// `^date` syntax. The list is still kept here as the single source
/// of truth for any future iOS resurrection of the chip row.
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
