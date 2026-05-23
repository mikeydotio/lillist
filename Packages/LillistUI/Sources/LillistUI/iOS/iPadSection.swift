#if os(iOS)
import SwiftUI

/// One of the three primary navigation destinations on iOS.
///
/// Plan 16 unified what used to be `TabShell.Tab` and
/// `SplitShell.Section` into a single type. The RCA / 3-tab plan
/// removes `.search` (Search becomes a top-leading toolbar sheet on
/// every section) and re-points `.all` from the tag tree to a true
/// "all open tasks" surface. The tag tree moves under `.filters`.
public enum iPadSection: String, Hashable, CaseIterable, Identifiable, Sendable {
    case today
    case all
    case filters

    public var id: Self { self }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .all: return "All"
        case .filters: return "Filters"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .all: return "checklist"
        case .filters: return "line.3.horizontal.decrease.circle"
        }
    }
}
#endif
