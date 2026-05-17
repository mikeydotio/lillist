import SwiftUI

// MARK: - Cross-platform "Increase Contrast" bridge
//
// SwiftUI's documented cross-platform API for the user's "Increase
// Contrast" preference is `\.colorSchemeContrast` (returns
// `ColorSchemeContrast.standard` / `.increased`). The boolean shape
// `accessibilityShouldIncreaseContrast` is iOS-only and not exposed on
// EnvironmentValues for macOS. We add the boolean computed view below
// so every callsite reads in the binary shape it actually uses
// (`if increaseContrast { … }`) without each one repeating the
// `colorSchemeContrast == .increased` comparison.

public extension EnvironmentValues {
    /// `true` when the user has enabled "Increase Contrast" in
    /// Accessibility settings on either platform. Computed from
    /// `colorSchemeContrast == .increased`, which is the SDK's
    /// cross-platform name.
    var accessibilityShouldIncreaseContrast: Bool {
        colorSchemeContrast == .increased
    }
}

// MARK: - Test-only environment overrides
//
// SDK 26.2 (Xcode 17) exposes `accessibilityReduceMotion`,
// `accessibilityReduceTransparency`, `accessibilityDifferentiateWithoutColor`,
// and `colorSchemeContrast` as read-only `KeyPath`s — they reflect the
// user's system Accessibility settings and cannot be overridden via
// `.environment(_:_:)` in snapshot tests.
//
// To still lock the env-honoring code paths under snapshot, we expose
// internal-only `*Override` env keys. Each helper modifier reads its
// override first; production code never touches the override key
// (it's `internal`, not `public`, so consumers can't set it from
// outside the LillistUI module). Tests using `@testable import LillistUI`
// inject via the override key for deterministic visual baselines.

struct ReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

struct ReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

struct DifferentiateWithoutColorOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

struct IncreaseContrastOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Snapshot-test only: when non-nil, replaces the system
    /// `accessibilityReduceMotion` value for views inside this subtree.
    /// Internal so consumers outside LillistUI can't accidentally set it.
    var reduceMotionOverride: Bool? {
        get { self[ReduceMotionOverrideKey.self] }
        set { self[ReduceMotionOverrideKey.self] = newValue }
    }

    var reduceTransparencyOverride: Bool? {
        get { self[ReduceTransparencyOverrideKey.self] }
        set { self[ReduceTransparencyOverrideKey.self] = newValue }
    }

    var differentiateWithoutColorOverride: Bool? {
        get { self[DifferentiateWithoutColorOverrideKey.self] }
        set { self[DifferentiateWithoutColorOverrideKey.self] = newValue }
    }

    var increaseContrastOverride: Bool? {
        get { self[IncreaseContrastOverrideKey.self] }
        set { self[IncreaseContrastOverrideKey.self] = newValue }
    }
}

/// View-modifier helpers that consult Apple's accessibility-environment
/// values. Each is a thin wrapper over the standard modifier plus an
/// `@Environment` read — no caching, no actor isolation, no shared state.
public extension View {
    /// `.animation(_:value:)` that no-ops under `accessibilityReduceMotion`.
    /// Use for decorative transitions (entrance/fade/slide). For animations
    /// that *communicate* state (swipe feedback), gate explicitly.
    func accessibleAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }

    /// Apply `material` as the background; substitute opaque `fallback`
    /// when `accessibilityReduceTransparency` is true.
    func accessibleMaterial<S: ShapeStyle>(
        _ material: Material,
        fallback: S,
        in shape: some Shape = Rectangle()
    ) -> some View {
        modifier(AccessibleMaterialModifier(
            material: material,
            fallback: AnyShapeStyle(fallback),
            shape: AnyShape(shape)
        ))
    }
}

private struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        let reduce = overrideReduceMotion ?? systemReduceMotion
        return content.animation(reduce ? nil : animation, value: value)
    }
}

private struct AccessibleMaterialModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var overrideReduceTransparency
    let material: Material
    let fallback: AnyShapeStyle
    let shape: AnyShape

    func body(content: Content) -> some View {
        let reduce = overrideReduceTransparency ?? systemReduceTransparency
        if reduce {
            content.background(fallback, in: shape)
        } else {
            content.background(material, in: shape)
        }
    }
}

/// Trait selector for the "Increase Contrast" preference. Callers read
/// the environment and pass it in: e.g.
/// `ContrastTuned.value(in: env, standard: .secondary, increased: .primary)`.
public enum ContrastTuned {
    @MainActor
    public static func value<T>(in environment: EnvironmentValues, standard: T, increased: T) -> T {
        environment.accessibilityShouldIncreaseContrast ? increased : standard
    }
}
