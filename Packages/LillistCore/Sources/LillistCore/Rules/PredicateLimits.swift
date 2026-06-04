import Foundation

/// Engine-wide numeric bounds shared by the predicate compiler, the pure-Swift
/// evaluator, and the CLI scope walks. Centralising these prevents the two
/// evaluators (and the CLI breadcrumb/scope traversals) from silently disagreeing
/// on how deep a parent chain is honoured.
public enum PredicateLimits {
    /// Maximum number of ancestor hops the engine honours when resolving
    /// `isDescendantOf` / `isAncestorOf` and when denormalising a task's
    /// ancestor set.
    ///
    /// The ceiling exists because `NSPredicate` cannot express transitive
    /// closure over a SQL store, so `NSPredicateCompiler.compileAncestor`
    /// unrolls a fixed number of `parent.…parent.id` key-paths. Every other
    /// traversal (the `SwiftEvaluator` snapshot walk, the CLI scope filters)
    /// matches this number so all paths agree on reachability.
    ///
    /// Tasks nested deeper than this are not matched by ancestor predicates.
    /// 8 is comfortably beyond any hand-authored hierarchy depth a user
    /// produces and keeps the unrolled predicate small.
    public static let maxAncestorDepth = 8
}
