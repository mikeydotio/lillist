#if os(iOS)
import SwiftUI

/// One of the four primary navigation destinations on iOS.
///
/// Plan 16 unifies what used to be `TabShell.Tab` and
/// `SplitShell.Section` (byte-equivalent enums that required manual
/// cross-conversion at the SplitShell boundary). Both shells now
/// consume this single type, and the keyboard-shortcut surface in
/// `LillistCommands` binds to it directly.
public enum iPadSection: String, Hashable, CaseIterable, Identifiable, Sendable {
    case today
    case all
    case filters
    case search

    public var id: Self { self }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .all: return "All"
        case .filters: return "Filters"
        case .search: return "Search"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .all: return "tag"
        case .filters: return "line.3.horizontal.decrease.circle"
        case .search: return "magnifyingglass"
        }
    }
}
#endif
