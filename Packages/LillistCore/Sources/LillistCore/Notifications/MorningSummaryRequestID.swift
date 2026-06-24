import Foundation

/// Well-known notification request identifier for the daily morning summary
/// (design Section 4 Layer 4). One per device.
public enum MorningSummary {
    public static let requestID = "io.mikey.lillist.morningSummary"
    public static let categoryID = "lillist.morningSummary"
}

/// Category identifier prefixes used by `NotificationCategoryFactory`.
/// One category per `NotificationKind`.
public enum NotificationCategoryID {
    public static func categoryID(for kind: NotificationKind) -> String {
        switch kind {
        case .defaultStart:    return "lillist.defaultStart"
        case .defaultDeadline: return "lillist.defaultDeadline"
        case .offsetStart:     return "lillist.offsetStart"
        case .offsetDeadline:  return "lillist.offsetDeadline"
        case .nudge:           return "lillist.nudge"
        }
    }
}
