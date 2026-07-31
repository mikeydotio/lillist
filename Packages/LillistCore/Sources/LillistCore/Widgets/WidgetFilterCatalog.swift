import Foundation

/// Runs `operation`, returning `nil` if it does not finish within `budget`.
///
/// This is **abandonment, not cancellation**, and the distinction is the whole
/// point. Standing up a Core Data stack is not cancellable — a structured
/// `withTaskGroup` race would still await the losing child on scope exit and so
/// would not bound anything. Here the work runs as an unstructured task that is
/// simply left to finish; callers that cache their result (see
/// `WidgetIntentSupport.Cache`) still benefit from it on the next call, so a slow
/// first open costs the fallback exactly once.
///
/// The nesting is meaningful: the outer optional is *this* function's
/// ("did it finish in time?"), the inner one is the operation's own value.
///
/// - Important: the abandoned task keeps its resources until it completes. Only
///   use this where that is acceptable and the work is idempotent or cached.
public func withBudget<T: Sendable>(
    _ budget: Duration,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    let work = Task { await operation() }
    let deadline = Task { try await Task.sleep(for: budget) }

    return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = ResumeGate(continuation)
        Task {
            let value = await work.value
            deadline.cancel()
            await gate.resume(with: value)
        }
        Task {
            guard (try? await deadline.value) != nil else { return }  // cancelled: work won
            await gate.resume(with: nil)
        }
    }
}

/// Ensures exactly one of the racing tasks resumes the continuation. Resuming a
/// `CheckedContinuation` twice traps, so the guard is a correctness requirement,
/// not defensiveness.
private actor ResumeGate<T: Sendable> {
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: T?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

/// Resolves the saved-filter list a widget's **configuration** surface needs,
/// cheapest source first and never waiting indefinitely.
///
/// `LIL-91`: the widget's `EntityQuery` used to answer every question by opening
/// the live Core Data store, unconditionally and without a bound. Three
/// consequences, all fixed here:
///
/// - **C1** — resolving *only* the ``WidgetSnapshot/unfilteredID`` sentinel did a
///   store read to answer a question whose answer is a compile-time constant.
///   That is the default configuration of every freshly added widget, so the most
///   common case paid the highest cost. ``resolve(ids:)`` now short-circuits.
/// - **C2** — nothing bounded the wait. `try?` catches a *throw*; nothing catches
///   a *hang*. In a process with a hard wall-clock budget, a blocked store open
///   meant WidgetKit never resolved the configuration intent and therefore never
///   called `timeline(for:in:)` — the widget rendered only its container
///   background. Every live read is now spent through ``withBudget(_:operation:)``.
/// - **C3** — the expensive source led and the cheap one was only a *throw*
///   fallback, so slowness (as distinct from failure) was unsurvivable. The
///   snapshot index is a plain file read and is entirely sufficient for a picker,
///   so it now leads; the live store is an enhancement, not a prerequisite.
///
/// Both sources are injected rather than reached for, so the policy above is
/// testable without a Core Data stack — the seam whose absence let this defect
/// survive.
public struct WidgetFilterCatalog: Sendable {
    public typealias Entry = WidgetSnapshotIndex.Entry

    /// The outcome of resolving a set of configuration identifiers.
    public struct Resolution: Sendable, Equatable {
        /// Whether the unfiltered "all tasks" sentinel was among the identifiers.
        public let includesUnfiltered: Bool
        /// The saved filters that matched, in catalog order.
        public let saved: [Entry]

        public init(includesUnfiltered: Bool, saved: [Entry]) {
            self.includesUnfiltered = includesUnfiltered
            self.saved = saved
        }
    }

    /// Wall-clock ceiling for a live-store read. Sized well inside WidgetKit's
    /// budget: overshooting it costs a stale-but-correct picker, whereas
    /// exceeding WidgetKit's costs the entire timeline.
    public static let defaultBudget: Duration = .milliseconds(800)

    private let budget: Duration
    private let indexRead: @Sendable () async -> [Entry]?
    private let liveRead: @Sendable () async -> [Entry]?

    /// - Parameters:
    ///   - budget: ceiling on the live read. Defaults to ``defaultBudget``.
    ///   - indexRead: the cheap source (the on-disk snapshot index). `nil` means
    ///     *unavailable*; an empty array means *authoritatively no filters* and is
    ///     an answer, not a miss.
    ///   - liveRead: the expensive source (the live store). Same `nil` semantics.
    public init(
        budget: Duration = WidgetFilterCatalog.defaultBudget,
        indexRead: @escaping @Sendable () async -> [Entry]?,
        liveRead: @escaping @Sendable () async -> [Entry]?
    ) {
        self.budget = budget
        self.indexRead = indexRead
        self.liveRead = liveRead
    }

    /// Every saved filter, cheap source first. Never blocks past ``budget``, and
    /// degrades to empty rather than stalling when neither source answers.
    public func filters() async -> [Entry] {
        if let fromIndex = await indexRead() { return fromIndex }
        let fromLive = await withBudget(budget) { await liveRead() }
        return fromLive.flatMap { $0 } ?? []
    }

    /// Resolve specific configuration identifiers.
    ///
    /// Returns without touching either source when the identifiers are fully
    /// satisfiable without one — i.e. the sentinel alone, or nothing at all (C1).
    public func resolve(ids: Set<UUID>) async -> Resolution {
        let includesUnfiltered = ids.contains(WidgetSnapshot.unfilteredID)
        let savedIDs = ids.subtracting([WidgetSnapshot.unfilteredID])
        guard savedIDs.isEmpty == false else {
            return Resolution(includesUnfiltered: includesUnfiltered, saved: [])
        }
        let matches = await filters().filter { savedIDs.contains($0.id) }
        return Resolution(includesUnfiltered: includesUnfiltered, saved: matches)
    }
}
