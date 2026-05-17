import SwiftUI
import LillistCore

/// The glyph displayed for each Status per design Section 7.
public enum StatusGlyph {
    public static func symbol(for status: Status) -> String {
        switch status {
        case .todo:    return "circle"
        case .started: return "circle.lefthalf.filled"
        case .blocked: return "circle.dashed"
        case .closed:  return "checkmark.circle.fill"
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
