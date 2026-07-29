import Foundation
import Network

/// Production `NetworkReachabilityProviding` backed by `NWPathMonitor`
/// (data-sync-hardening `S24`).
///
/// `NWPathMonitor`'s API predates Swift concurrency (a queue-dispatched
/// callback, not an `async` sequence), so this actor owns the monitor
/// exclusively, starts it once, and mirrors every path update into a
/// single actor-isolated `Bool` that `isReachable()` reads — the same
/// "wrap a callback-based framework type behind an actor-isolated cache"
/// shape `AccountStateMonitor`/`CloudKitEventBridge` already use for their
/// own non-Sendable framework types.
///
/// Placed in `LillistCore` (not duplicated per app target) because it
/// imports only `Network` + `Foundation` — no platform-specific behavior
/// exists between iOS and macOS here — extending the precedent
/// `StoreLocation` set (Wave 1c): one canonical implementation beats two
/// per-app copies of the identical wrapper.
public actor LiveNetworkReachability: NetworkReachabilityProviding {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    /// Defaults `true` so a monitor that hasn't `start()`ed yet — or
    /// hasn't received its first path update — never falsely reports
    /// offline and pauses sync for no reason.
    private var reachable: Bool = true
    private var started = false

    public init(queue: DispatchQueue = DispatchQueue(label: "app.lillist.network-reachability")) {
        self.monitor = NWPathMonitor()
        self.queue = queue
    }

    /// Begin observing path updates. Idempotent — a second call is a
    /// no-op. Must be called before `isReachable()` reflects live network
    /// state.
    public func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let isUp = path.status == .satisfied
            Task { await self?.setReachable(isUp) }
        }
        monitor.start(queue: queue)
    }

    public func isReachable() async -> Bool {
        reachable
    }

    private func setReachable(_ value: Bool) {
        reachable = value
    }

    deinit {
        monitor.cancel()
    }
}
