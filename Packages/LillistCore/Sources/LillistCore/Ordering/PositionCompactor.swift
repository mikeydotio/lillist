import Foundation

/// Re-spaces a list of fractional positions with even gaps of 1.0.
///
/// Caller is responsible for passing a list already in the desired order
/// (typically `[siblings].sorted(by: { $0.position < $1.position })`).
/// The compactor preserves that order and just normalizes the values.
public enum PositionCompactor {
    public static func recompact(positions: [Double]) -> [Double] {
        positions.enumerated().map { index, _ in Double(index + 1) }
    }
}
