import Foundation

/// Cross-process handoff for "open Quick Capture, optionally pre-filled".
///
/// The App Intents extension runs in a *separate process* from the app, so
/// `NotificationCenter` can't carry the signal. Instead the intent stashes the
/// seed text in the shared App Group `UserDefaults`; the app drains it when it
/// next becomes active (cold launch via `bootstrap()`, warm via the
/// `didBecomeActive` observer) and opens the capture dialog pre-filled.
///
/// Presence of a stashed value — *even an empty string* — means "open the
/// dialog"; the string itself is the prefill. A short TTL guards against a
/// stale seed (e.g. the intent ran but the app never foregrounded) re-firing
/// the dialog on an unrelated later activation.
public enum QuickCaptureHandoff {
    private static let seedKey = "lillist.handoff.quickCaptureSeed"
    private static let stampKey = "lillist.handoff.quickCaptureSeedAt"

    /// How long a stashed seed stays valid. The app normally consumes it
    /// within a second of the intent running; 30s is generous slack for a
    /// cold launch while still discarding a truly stale seed.
    public static let ttl: TimeInterval = 30

    /// Stash the seed text. The app opens an *empty* capture dialog for `""`.
    /// - Parameters:
    ///   - appGroupID: The App Group suite shared by the app and extension.
    ///   - now: Injectable clock for tests.
    public static func stash(_ text: String, appGroupID: String, now: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(text, forKey: seedKey)
        defaults.set(now.timeIntervalSince1970, forKey: stampKey)
    }

    /// Atomically read **and clear** the seed. Returns `nil` when absent or
    /// older than ``ttl``. A non-nil result (including `""`) means "open the
    /// dialog with this prefill".
    /// - Parameters:
    ///   - appGroupID: The App Group suite shared by the app and extension.
    ///   - now: Injectable clock for tests.
    public static func take(appGroupID: String, now: Date = Date()) -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        guard defaults.object(forKey: seedKey) != nil else { return nil }
        let stamp = defaults.double(forKey: stampKey)
        let text = defaults.string(forKey: seedKey) ?? ""
        // Always clear — a stale seed must never accumulate or re-fire.
        defaults.removeObject(forKey: seedKey)
        defaults.removeObject(forKey: stampKey)
        guard now.timeIntervalSince1970 - stamp <= ttl else { return nil }
        return text
    }
}
