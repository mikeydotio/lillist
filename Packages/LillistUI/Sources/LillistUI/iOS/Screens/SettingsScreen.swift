#if os(iOS)
import SwiftUI

/// iOS Settings shell — `NavigationStack` + `Form` + inline navigation
/// title + Done toolbar button. The Form's sections themselves are
/// supplied by the caller via the `@SectionsContent` builder so the
/// iOS app target keeps its env-dependent sections (`GeneralSection`,
/// `NotificationsSection`, `TrashSection`, `QuickCaptureSection`,
/// `CrashReportingSection`, `AdvancedSection`) co-located with the
/// stores they read, while `IOSScreenTourTests` can pass simple mock
/// `Section` views to verify the shell layout.
///
/// Plan 20a Task 4e. Per the architect+QA vote on Plan 20a's
/// SettingsTab subquestion, the body migrates the *navigation chrome*
/// only; the sections stay in the iOS app target where their
/// `AppEnvironment` dependencies live.
public struct SettingsScreen<SectionsContent: View>: View {
    public var sections: SectionsContent
    public var onDone: @MainActor () -> Void

    public init(
        onDone: @escaping @MainActor () -> Void = {},
        @ViewBuilder sections: () -> SectionsContent
    ) {
        self.onDone = onDone
        self.sections = sections()
    }

    public var body: some View {
        NavigationStack {
            Form {
                sections
                    // Rainbow Logic settings chrome, applied to the
                    // builder content so every app-target section
                    // inherits without knowing about the theme:
                    // card-surface rows on the cool-gray workspace and
                    // the tactile switch (the full-whimsy decision). The
                    // form-level chrome (switch style, workspace fill) is
                    // shared with each pushed `SettingsDetailScreen` via
                    // `settingsFormStyle()` so landing + sub-pages match.
                    .listRowBackground(LillistColor.card)
            }
            .settingsFormStyle()
            .navigationTitle(Text(String(localized: "Settings", bundle: .module)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", bundle: .module)) {
                        onDone()
                    }
                }
            }
        }
    }
}
#endif
