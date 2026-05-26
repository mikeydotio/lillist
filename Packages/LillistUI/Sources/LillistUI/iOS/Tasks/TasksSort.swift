#if os(iOS)
import Foundation

/// Sort option exposed by the iOS Tasks screen's sort menu.
///
/// - `personalized`: per-parent fractional `position` (`TaskStore.reorder`).
/// - `due`: ascending by `deadline`, with `nil` deadlines pushed to the end of each level.
/// - `modified`: descending by `modifiedAt`, with `nil` pushed to the end of each level.
///
/// Persisted via `@AppStorage("lillist.ios.sort")` as `rawValue`.
public enum TasksSort: String, CaseIterable, Identifiable, Sendable {
    case personalized
    case due
    case modified

    public var id: String { rawValue }
}
#endif
