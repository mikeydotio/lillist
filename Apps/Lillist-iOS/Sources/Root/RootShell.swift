import SwiftUI
import LillistUI

/// Top-level adaptive shell. Compact ⇒ `TabShell`, regular ⇒ `SplitShell`.
/// Design Section 7 iOS subsection.
struct RootShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        switch SizeClassRouter.layout(for: horizontalSizeClass) {
        case .tab:
            TabShell()
        case .split:
            SplitShell()
        }
    }
}
