#if os(iOS)
import SwiftUI

/// The Rainbow Logic settings-form chrome shared by the Settings
/// landing screen (`SettingsScreen`) and every drill-down sub-page
/// (`SettingsDetailScreen`): the tactile rainbow switch, a hidden
/// system scroll background, and the cool-gray workspace fill. Form
/// rows pick up the card surface separately via `.listRowBackground`
/// so each section inherits it without knowing about the theme.
struct SettingsFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toggleStyle(.rainbow)
            .scrollContentBackground(.hidden)
            .background(LillistColor.workspace)
    }
}

extension View {
    /// Apply the shared Settings form chrome (see `SettingsFormStyle`).
    func settingsFormStyle() -> some View { modifier(SettingsFormStyle()) }
}

/// A pushed Settings sub-page: a `Form` of caller-supplied sections
/// wrapped in the same chrome `SettingsScreen` uses, plus an inline
/// navigation title. It deliberately owns **no** `NavigationStack` —
/// it is presented inside the landing screen's stack via a
/// `NavigationLink`, so adding another stack here would break the
/// back button. The env-coupled sections themselves stay in the app
/// target (where their `AppEnvironment` dependencies live); this type
/// only supplies the chrome, mirroring `SettingsScreen`'s split.
public struct SettingsDetailScreen<Content: View>: View {
    private let title: LocalizedStringKey
    private let content: Content

    public init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        Form {
            content
                .listRowBackground(LillistColor.card)
        }
        .settingsFormStyle()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
