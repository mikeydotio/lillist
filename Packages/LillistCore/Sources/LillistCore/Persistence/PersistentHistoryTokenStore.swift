import Foundation
import CoreData

/// Persists the last-processed `NSPersistentHistoryToken` so the
/// `RemoteChangeReconciler` resumes history diffing across launches instead
/// of replaying the whole store every time.
///
/// The token is archived with `NSKeyedArchiver` (the documented way to
/// persist an `NSPersistentHistoryToken`) into App-Group `UserDefaults`, so
/// the main app and its extensions share one watermark. `@unchecked Sendable`
/// because `UserDefaults` is internally thread-safe and the only mutable state
/// is delegated to it.
public final class PersistentHistoryTokenStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    /// The reconciler's watermark key (the historical default).
    public static let defaultKey = "io.mikey.lillist.persistentHistoryToken"
    /// The diagnostics observer's watermark key. Distinct from `defaultKey` so
    /// the two history consumers never clobber each other's progress.
    public static let diagnosticsKey = "io.mikey.lillist.diagnostics.historyToken"

    /// Backed by an explicit suite (tests) or the App Group (production).
    /// `key` selects which consumer's watermark this store reads/writes.
    public init(suiteName: String, key: String = PersistentHistoryTokenStore.defaultKey) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.key = key
    }

    /// Backed by the App Group's shared defaults, falling back to `.standard`
    /// when the group container is unreachable (unsigned/test contexts).
    public init(appGroupID: String, key: String = PersistentHistoryTokenStore.defaultKey) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        self.key = key
    }

    /// The last persistent-history token the reconciler has consumed, or `nil`
    /// if none has been recorded (fresh install / cleared).
    public var lastToken: NSPersistentHistoryToken? {
        get {
            guard let data = defaults.data(forKey: self.key) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            )
        }
        set {
            guard let token = newValue else {
                defaults.removeObject(forKey: self.key)
                return
            }
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            ) {
                defaults.set(data, forKey: self.key)
            }
        }
    }
}
