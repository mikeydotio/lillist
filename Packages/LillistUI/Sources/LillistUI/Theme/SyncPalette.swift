import SwiftUI

/// Canonical sync-indicator palette. Single source of truth for
/// `SyncIndicator → (Color, SF Symbol)` across macOS (`SyncStatusDotView`)
/// and iOS (`SyncStatusBadge`).
///
/// Plan 14 unified the two per-platform `switch` statements that had
/// drifted: the iOS badge previously returned `.green` for any `.idle`
/// regardless of age, while the macOS dot returned `.yellow` for stale
/// idles and `.green` only for recent ones. The macOS rule was
/// canonical (and matches design Section 8); this extension encodes it
/// for both platforms.
public extension SyncIndicator {
    /// Threshold for "recently synced" in seconds. Idles newer than this
    /// render green; older render yellow.
    static let recencyWindow: TimeInterval = 60

    /// The tint color for this indicator's dot/badge.
    /// - `.idle(nil)` → `.secondary` (never synced)
    /// - `.idle(within recencyWindow)` → `.green`
    /// - `.idle(older)` → `.yellow`
    /// - `.inProgress` → `.blue`
    /// - `.error` → `.red`
    var color: Color {
        switch self {
        case .idle(let last):
            guard let last else { return .secondary }
            return Date().timeIntervalSince(last) < Self.recencyWindow ? .green : .yellow
        case .inProgress:
            return .blue
        case .error:
            return .red
        }
    }

    /// The SF Symbol name for this indicator. Some surfaces (the iOS
    /// badge today) render only a dot; the symbol is available for
    /// surfaces that include a glyph alongside the tint.
    /// - `.idle` → `checkmark`
    /// - `.inProgress` → `arrow.triangle.2.circlepath`
    /// - `.error` → `exclamationmark.triangle.fill`
    var systemImage: String {
        switch self {
        case .idle: return "checkmark"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// SF Symbol overlaid on the dot when
    /// `accessibilityDifferentiateWithoutColor` is true. Each shape is
    /// visually distinct from the other three, even rendered in a single
    /// foreground color. Plan 17 introduced this as the shape axis for
    /// the differentiate-without-color preference.
    var differentiatedSystemImage: String {
        switch self {
        case .idle(let last):
            guard let last else { return "circle" }
            return Date().timeIntervalSince(last) < Self.recencyWindow ? "circle.fill" : "circle.dotted"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
