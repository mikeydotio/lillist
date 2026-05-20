import Foundation

/// Per-device preferences kept in App Group `UserDefaults`.
///
/// Plan 21 partitions Lillist's preferences into two stores:
///
/// - **`DevicePreferencesStore`** (this file) — values whose meaning is
///   tied to *this device*: the onboarding-completion gate, the
///   macOS Quick Capture hotkey, the macOS status-bar visibility, the
///   per-device crash-prompt opt-in. Lives in App Group
///   `UserDefaults(suiteName:)` so the iOS Share Extension, the
///   Shortcuts (App Intents) extension, and the `lillist` CLI see the
///   same values.
/// - **`PreferencesStore`** — values that belong to the user's account
///   and should sync via CloudKit: notification cadence, trash retention,
///   default sort, default tag tint. Lives in Core Data's
///   `AppPreferences` row.
///
/// The partition exists so a sync-mode migration (destructive wipe of
/// the local Core Data store, or wholesale upload to iCloud) cannot
/// accidentally overwrite a value that the user expects to stay
/// device-local. See the migration design in the Plan 21 spec.
///
/// All keys are namespaced under `lillist.devicePrefs.` to leave room
/// for future App Group consumers without colliding.
public actor DevicePreferencesStore {
    private let defaults: UserDefaults

    /// - Parameter appGroupID: The App Group identifier shared between
    ///   the main app, extensions, and the CLI. When the App Group is
    ///   unreachable (e.g. tests run outside a signed sandbox) we fall
    ///   back to `.standard` so the store stays usable.
    public init(appGroupID: String) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Test/preview helper: build a store backed by a UserDefaults
    /// suite created from the given name. Each invocation builds its
    /// own `UserDefaults` instance so callers don't have to send a
    /// shared non-Sendable reference across actor boundaries — multiple
    /// stores built from the same name still observe each other's
    /// writes because `UserDefaults(suiteName:)` returns a view onto
    /// the named domain.
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: Onboarding completion

    private static let onboardingKey = "lillist.devicePrefs.hasCompletedOnboarding"
    /// Whether the user has completed the one-screen onboarding on this
    /// device. Survives Core Data store deletion (Plan 21 regression
    /// guard).
    public func hasCompletedOnboarding() -> Bool {
        defaults.bool(forKey: Self.onboardingKey)
    }
    public func setHasCompletedOnboarding(_ value: Bool) {
        defaults.set(value, forKey: Self.onboardingKey)
    }

    // MARK: Quick Capture

    private static let quickCaptureEnabledKey = "lillist.devicePrefs.quickCaptureEnabled"
    /// Whether the user wants the global Quick Capture affordance
    /// surfaced. Default `true`. iOS interprets this as "show the
    /// floating + button"; macOS as "the global hotkey is active".
    public func quickCaptureEnabled() -> Bool {
        if defaults.object(forKey: Self.quickCaptureEnabledKey) == nil { return true }
        return defaults.bool(forKey: Self.quickCaptureEnabledKey)
    }
    public func setQuickCaptureEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.quickCaptureEnabledKey)
    }

    private static let quickCaptureHotkeyKey = "lillist.devicePrefs.quickCaptureHotkey"
    /// Default hotkey spec when the user hasn't customised one.
    public static let quickCaptureHotkeyDefault = "ctrl+opt+space"
    /// macOS-only hotkey string (e.g. `"ctrl+opt+space"`). iOS reads it
    /// to stay shape-compatible but never wires it to anything.
    public func quickCaptureHotkey() -> String {
        defaults.string(forKey: Self.quickCaptureHotkeyKey) ?? Self.quickCaptureHotkeyDefault
    }
    public func setQuickCaptureHotkey(_ value: String) {
        defaults.set(value, forKey: Self.quickCaptureHotkeyKey)
    }

    // MARK: Status bar (macOS)

    private static let statusBarVisibleKey = "lillist.devicePrefs.statusBarItemVisible"
    /// macOS status-bar icon visibility. iOS reads it for shape parity
    /// but ignores it.
    public func statusBarItemVisible() -> Bool {
        if defaults.object(forKey: Self.statusBarVisibleKey) == nil { return true }
        return defaults.bool(forKey: Self.statusBarVisibleKey)
    }
    public func setStatusBarItemVisible(_ value: Bool) {
        defaults.set(value, forKey: Self.statusBarVisibleKey)
    }

    // MARK: Crash prompts

    private static let crashPromptsKey = "lillist.devicePrefs.crashPromptsEnabled"
    /// Whether the post-crash report sheet is shown on next launch.
    /// Per-device because crash UX targets the user on the affected
    /// machine — silencing crash prompts on the iPad shouldn't silence
    /// them on the Mac.
    public func crashPromptsEnabled() -> Bool {
        if defaults.object(forKey: Self.crashPromptsKey) == nil { return true }
        return defaults.bool(forKey: Self.crashPromptsKey)
    }
    public func setCrashPromptsEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.crashPromptsKey)
    }

    // MARK: One-time migration marker

    private static let migrationFlagKey = "lillist.devicePrefs.cdPartitionMigrationCompleted"
    /// `true` once `AppPreferencesPartitionMigrator` has copied the
    /// pre-Plan-21 values out of Core Data into this store. The
    /// migrator is idempotent; this flag short-circuits subsequent
    /// runs.
    public var migrationFromCoreDataCompleted: Bool {
        defaults.bool(forKey: Self.migrationFlagKey)
    }
    public func markMigrationFromCoreDataCompleted() {
        defaults.set(true, forKey: Self.migrationFlagKey)
    }
}
