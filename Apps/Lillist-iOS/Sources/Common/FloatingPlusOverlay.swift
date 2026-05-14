import SwiftUI
import LillistUI

/// Drives the floating "+" button positioned bottom-trailing on every primary
/// surface. Tapping the button sets `isPresented = true`, which the parent
/// view uses to present the Quick Capture sheet. Replaced (or extended) by
/// Task 8.
struct FloatingPlusOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        FloatingAddButton(onTap: { isPresented = true })
    }
}
