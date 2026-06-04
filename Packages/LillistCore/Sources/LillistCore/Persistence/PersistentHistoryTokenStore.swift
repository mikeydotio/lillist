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
    private static let key = "com.mikeydotio.lillist.persistentHistoryToken"

    /// Backed by an explicit suite (tests) or the App Group (production).
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Backed by the App Group's shared defaults, falling back to `.standard`
    /// when the group container is unreachable (unsigned/test contexts).
    public init(appGroupID: String) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// The last persistent-history token the reconciler has consumed, or `nil`
    /// if none has been recorded (fresh install / cleared).
    public var lastToken: NSPersistentHistoryToken? {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            )
        }
        set {
            guard let token = newValue else {
                defaults.removeObject(forKey: Self.key)
                return
            }
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            ) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }
}
