#if os(macOS)
import SwiftUI
import SnapshotTesting

/// Wraps a view with deterministic environment for snapshotting.
struct SnapshotHost<Content: View>: View {
    let colorScheme: ColorScheme
    let content: () -> Content
    var body: some View {
        content()
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(minWidth: 320, minHeight: 240)
    }
}
#endif
