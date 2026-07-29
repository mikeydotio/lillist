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
///
/// **Registration is closed by construction** (data-sync-hardening
/// `X12`/`L7`): the `key` a store reads/writes is derived from a
/// `HistoryConsumerID` case, never an arbitrary `String` — see
/// `WatermarkRegistry`'s own doc comment (`Persistence/WatermarkRegistry.swift`)
/// for why. A fourth history consumer registers by adding a case there, not
/// by handing this initializer a new string.
public final class PersistentHistoryTokenStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    /// Backed by an explicit suite (tests) or the App Group (production).
    /// `consumer` selects which registered consumer's watermark this store
    /// reads/writes; defaults to `.remoteChangeReconciler`, the historical
    /// default, for every call site that doesn't care which consumer it is.
    public init(suiteName: String, consumer: HistoryConsumerID = .remoteChangeReconciler) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.key = consumer.tokenDefaultsKey
    }

    /// Backed by the App Group's shared defaults, falling back to `.standard`
    /// when the group container is unreachable (unsigned/test contexts).
    public init(appGroupID: String, consumer: HistoryConsumerID = .remoteChangeReconciler) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        self.key = consumer.tokenDefaultsKey
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
