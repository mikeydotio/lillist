import Foundation

/// Typed, value-based navigation destinations pushed from the Filters
/// tab's NavigationStack. The enum exists so `NavigationPath` can be
/// round-tripped through `Codable` for scene state restoration — bare
/// destination views (the old `NavigationLink { AllTagsView() }`
/// pattern) put non-codable items on the path and break that codec.
///
/// Filter rows and tag rows still push bare `UUID`s — those resolve
/// through `.navigationDestination(for: UUID.self)` modifiers on the
/// receiving views (`FiltersListView`, `AllTagsView`). Only the
/// intermediate "All Tags" hop needs a typed value, and that's what
/// this enum carries.
enum FiltersDestination: Hashable, Codable, Sendable {
    case allTags
}
