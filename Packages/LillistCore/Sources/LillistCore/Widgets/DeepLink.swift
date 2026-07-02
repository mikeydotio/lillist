import Foundation

/// The `lillist://` deep links the widget (and, in future, notifications) use to
/// drive the app. Pure Foundation — parser and builder in one place so the
/// widget that *emits* a link and the app that *handles* it can't drift.
///
/// Shapes:
/// - `lillist://quickcapture`      — open Quick Capture
/// - `lillist://filter/<uuid>`     — open the app focused on a saved filter
/// - `lillist://task/<uuid>`       — open a specific task
public enum DeepLink: Equatable, Sendable {
    case quickCapture
    case filter(UUID)
    case task(UUID)

    /// The registered URL scheme (see each app's Info.plist `CFBundleURLTypes`).
    public static let scheme = "lillist"

    /// Parse an inbound URL. Returns `nil` for anything that isn't a recognized
    /// Lillist deep link.
    public init?(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.scheme == Self.scheme
        else { return nil }

        let firstPathComponent = comps.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init)

        switch comps.host {
        case "quickcapture":
            self = .quickCapture
        case "filter":
            guard let raw = firstPathComponent, let id = UUID(uuidString: raw) else { return nil }
            self = .filter(id)
        case "task":
            guard let raw = firstPathComponent, let id = UUID(uuidString: raw) else { return nil }
            self = .task(id)
        default:
            return nil
        }
    }

    /// The URL for this link (for the widget to emit).
    public var url: URL {
        switch self {
        case .quickCapture:
            return URL(string: "\(Self.scheme)://quickcapture")!
        case .filter(let id):
            return URL(string: "\(Self.scheme)://filter/\(id.uuidString)")!
        case .task(let id):
            return URL(string: "\(Self.scheme)://task/\(id.uuidString)")!
        }
    }
}
