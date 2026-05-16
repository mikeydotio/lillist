import LillistCore

/// Display labels for `SortField` cases used in Preferences. Previously
/// duplicated verbatim in iOS `GeneralSection.swift` and macOS
/// `GeneralPane.swift` as `private extension SortField`. Plan 14 lifts
/// the extension into LillistUI and drops `private` to make it visible
/// to both app targets.
public extension SortField {
    var displayName: String {
        switch self {
        case .manualPosition: return "Manual"
        case .start: return "Start date"
        case .deadline: return "Deadline"
        case .title: return "Title"
        case .createdAt: return "Created"
        case .modifiedAt: return "Modified"
        case .closedAt: return "Closed"
        case .status: return "Status"
        }
    }
}
