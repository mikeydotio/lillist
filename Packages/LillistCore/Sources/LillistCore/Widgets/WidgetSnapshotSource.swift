import Foundation

/// The reads ``WidgetSnapshotBuilder`` needs in order to build a snapshot — and
/// nothing else.
///
/// `LIL-93`: the builder previously took a *concrete* `SmartFilterStore`, so
/// there was no way to hand it a store that fails. Every error branch in
/// `performRegenerate` was therefore unreachable from a test, and that
/// untestability is precisely why the `C4` defect (a thrown read persisted as an
/// authoritative *empty* snapshot) survived from 2026-07-02 to 2026-07-31 and
/// had to be fixed in `04136f2f` **without** a regression test. This protocol is
/// that fix's missing preventative action.
///
/// Three requirements, matching the three reads the builder actually performs.
/// Interface Segregation is the point: `SmartFilterStore`'s full surface is
/// large and Core-Data-bound, and a fake owing all of it would be unwritable.
///
/// - Note: the names deliberately **do not** mirror `SmartFilterStore`'s
///   (`list`, `evaluate`). Its `evaluate` overloads carry default arguments
///   (`now:`, `calendar:`, `includeArchived:`, `limit:`, `offset:`), and Swift
///   neither lets a method with defaults witness a requirement declaring fewer
///   parameters, nor permits defaults on a requirement itself. Distinct names
///   sidestep both problems and keep the conformance three plain forwarding
///   calls with no overload ambiguity.
public protocol WidgetSnapshotSource: Sendable {
    /// Every saved smart filter, in canonical order.
    func listFilters() async throws -> [SmartFilterStore.SmartFilterRecord]

    /// The tasks matching one saved filter, in that filter's own sort order.
    func evaluateFilter(id: UUID) async throws -> [TaskStore.TaskRecord]

    /// The tasks matching an ad-hoc predicate group — the builder's sentinel
    /// ("all open tasks") and grace-set ("closed today") reads.
    func evaluateGroup(
        _ group: PredicateGroup,
        sort: SortField,
        ascending: Bool
    ) async throws -> [TaskStore.TaskRecord]
}

/// The production conformance: pure forwarding, no behavior of its own.
extension SmartFilterStore: WidgetSnapshotSource {
    public func listFilters() async throws -> [SmartFilterRecord] {
        try await list()
    }

    public func evaluateFilter(id: UUID) async throws -> [TaskStore.TaskRecord] {
        try await evaluate(id: id)
    }

    public func evaluateGroup(
        _ group: PredicateGroup,
        sort: SortField,
        ascending: Bool
    ) async throws -> [TaskStore.TaskRecord] {
        try await evaluate(group: group, sort: sort, ascending: ascending)
    }
}
