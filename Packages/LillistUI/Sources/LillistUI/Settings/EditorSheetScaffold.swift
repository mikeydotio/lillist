import SwiftUI

/// Chrome-light scaffold shared by ``TagEditorSheet`` and ``FilterEditorSheet``.
///
/// A fixed Cancel / title / Save header over a grouped `Form` of caller-supplied
/// fields. Follows the codebase's cross-platform sheet convention (no
/// `NavigationStack`; the presenting page/pane sizes it via `.presentationDetents`
/// on iOS and a `.frame` on macOS) so one layout serves both platforms.
struct EditorSheetScaffold<Fields: View>: View {
    let title: Text
    let isSaveEnabled: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) { Text("Cancel", bundle: .module) }
                Spacer()
                title.font(.headline)
                Spacer()
                Button(action: onSave) {
                    Text("Save", bundle: .module).fontWeight(.semibold)
                }
                .disabled(!isSaveEnabled)
            }
            .padding(LillistSpacing.l)

            Form {
                fields()
                    .listRowBackground(LillistColor.card)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(LillistColor.workspace)
        #if os(macOS)
        .frame(width: 420, height: 320)
        #endif
    }
}
