#if os(iOS)
import SwiftUI

/// Maps a horizontal size class to the iOS layout that design Section 7's
/// "iOS / iPadOS adaptive UI" subsection specifies. Conservative default:
/// a `nil` size class is treated as compact (tab-based layout).
public enum SizeClassRouter {
    public enum Layout: Equatable, Sendable { case tab, split }

    public static func layout(for sizeClass: UserInterfaceSizeClass?) -> Layout {
        sizeClass == .regular ? .split : .tab
    }
}
#endif
