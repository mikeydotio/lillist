import SwiftUI

/// PreferenceKey collecting the frames of every row that's currently
/// in `DragReorderable`. Aggregates a `[UUID: CGRect]` keyed by row id
/// in the named coordinate space `"TaskListDrag"`. The screen reads
/// this preference via `.onPreferenceChange` and feeds it to the
/// controller as `controller.geometry`.
public struct RowFramePreferenceKey: PreferenceKey {
    public static let defaultValue: [UUID: CGRect] = [:]
    public static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Coordinate space name shared by the list container, every row's
/// frame reporter, and the drag gesture.
public enum DragCoordinateSpace {
    public static let name: String = "TaskListDrag"
}

extension View {
    /// Reports this view's frame as a single-key dictionary entry to
    /// the enclosing `RowFramePreferenceKey`. The row's `.background`
    /// reads geometry via `GeometryReader`; rendering is otherwise
    /// unaffected.
    func reportRowGeometry(id: UUID) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(DragCoordinateSpace.name))]
                )
            }
        )
    }
}
