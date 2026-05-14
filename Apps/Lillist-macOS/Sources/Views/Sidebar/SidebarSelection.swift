import Foundation

/// What the user has selected in the sidebar. Drives the middle column.
enum SidebarSelection: Hashable, Codable, Sendable {
    case pinnedTask(UUID)
    case pinnedFilter(UUID)
    case tag(UUID)
    case filter(UUID)
    case trash
}
