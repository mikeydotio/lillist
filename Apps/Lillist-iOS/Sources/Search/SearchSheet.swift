import SwiftUI
import LillistUI

/// Wraps `SearchView` for sheet presentation from the top-leading
/// toolbar button on every primary section. The RCA / 3-tab restructure
/// removes the Search tab; this wrapper preserves the same
/// `NavigationStack + navigationDestination` shape SearchView relied on
/// when it was the root of a tab, so search-result row taps still push
/// into a `TaskDetailView`.
struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SearchView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Text(String(localized: "Done"))
                        }
                        .accessibilityIdentifier("SearchDoneButton")
                    }
                }
        }
    }
}

/// Top-leading toolbar item that opens the Search sheet — mirrors the
/// position of `SettingsToolbarItem` on the trailing edge.
struct SearchToolbarItem: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(String(localized: "Search"))
                .accessibilityIdentifier("SearchToolbarButton")
            }
        }
    }
}
