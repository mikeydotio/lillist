import SwiftUI
import LillistUI

/// Scene-level state bindings owned by `LillistApp` and consumed by
/// shells / commands deep in the view tree. Plan 16 Task 29 moves the
/// Quick-Capture trigger and the active-section selection up to the
/// Scene so `LillistCommands` (a `Commands` struct) can bind to them
/// from outside any specific view.
struct IsQuickCapturePresentedBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

struct SelectedSectionBindingKey: EnvironmentKey {
    static let defaultValue: Binding<iPadSection?> = .constant(nil)
}

/// RCA / 3-tab restructure: Search lives in a sheet presented from the
/// top-leading toolbar button on every primary section. The binding is
/// owned by `LillistApp` so `LillistCommands` (Scene-level) can also
/// trigger it via ⌘⇧F.
struct IsSearchPresentedBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

/// Filters-tab `NavigationStack` path lifted to `LillistApp` so it can
/// be encoded into / decoded from `@AppStorage` for state restoration
/// (Plan: state-restoration). Both `TabShell` and `SplitShell` bind
/// their Filters-tab NavigationStack to this single source of truth.
struct FiltersPathBindingKey: EnvironmentKey {
    // `Binding<NavigationPath>` isn't `Sendable` (NavigationPath has
    // no `Sendable` conformance), but `EnvironmentKey.defaultValue`
    // must be nonisolated. The value is a `.constant(...)` no-op
    // binding — it never mutates — so the data-race risk the checker
    // warns about doesn't exist here.
    nonisolated(unsafe) static let defaultValue: Binding<NavigationPath> = .constant(NavigationPath())
}

extension EnvironmentValues {
    var isQuickCapturePresentedBinding: Binding<Bool> {
        get { self[IsQuickCapturePresentedBindingKey.self] }
        set { self[IsQuickCapturePresentedBindingKey.self] = newValue }
    }

    var selectedSectionBinding: Binding<iPadSection?> {
        get { self[SelectedSectionBindingKey.self] }
        set { self[SelectedSectionBindingKey.self] = newValue }
    }

    var isSearchPresentedBinding: Binding<Bool> {
        get { self[IsSearchPresentedBindingKey.self] }
        set { self[IsSearchPresentedBindingKey.self] = newValue }
    }

    var filtersPathBinding: Binding<NavigationPath> {
        get { self[FiltersPathBindingKey.self] }
        set { self[FiltersPathBindingKey.self] = newValue }
    }
}
