import SwiftUI
import LillistCore

/// The glyph displayed for each Status per design Section 7.
///
/// Square-family SF Symbols, echoing the squircle status chip
/// (`StatusCubeView`): the menu and macOS detail picker now read as the
/// same shape language as the row control.
public enum StatusGlyph {
    public static func symbol(for status: Status) -> String {
        switch status {
        case .todo:    return "square"
        case .started: return "square.lefthalf.filled"
        case .blocked: return "square.dashed"
        case .closed:  return "checkmark.square.fill"
        }
    }

    public static func accessibilityLabel(for status: Status) -> String {
        switch status {
        case .todo:    return String(localized: "To do", bundle: .module)
        case .started: return String(localized: "Started", bundle: .module)
        case .blocked: return String(localized: "Blocked", bundle: .module)
        case .closed:  return String(localized: "Closed", bundle: .module)
        }
    }
}
