import Foundation

extension PreferencesStore.Prefs {
    /// Default value for `crashPromptsEnabled`. Per design Section 8,
    /// the post-crash report sheet is on by default — the user
    /// explicitly opts *out* if they prefer not to see prompts.
    public static var crashPromptsDefault: Bool { true }
}
