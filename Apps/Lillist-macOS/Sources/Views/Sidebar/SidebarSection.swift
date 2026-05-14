import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case pinned, tags, filters, trash
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pinned: return "Pinned"
        case .tags:   return "Tags"
        case .filters:return "Filters"
        case .trash:  return "Trash"
        }
    }
}
