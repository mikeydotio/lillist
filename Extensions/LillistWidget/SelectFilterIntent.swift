import AppIntents

/// The widget's configuration intent: which saved smart filter to display.
///
/// `filter` is optional — when unset (a freshly added widget), the timeline
/// provider falls back to the first available filter, so the widget shows
/// something useful before the user picks.
struct SelectFilterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Filter"
    static let description = IntentDescription("Choose which saved smart filter the widget shows.")

    @Parameter(title: "Filter")
    var filter: SmartFilterEntity?

    init() {}

    init(filter: SmartFilterEntity?) {
        self.filter = filter
    }
}
