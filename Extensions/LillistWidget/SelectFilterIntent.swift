import AppIntents

/// The widget's configuration intent: which saved smart filter to display.
///
/// Defaults to the **"No Filter"** sentinel (all tasks) so a freshly added
/// widget is immediately useful and unambiguous. The timeline provider treats
/// both the sentinel id and a missing value as unfiltered.
struct SelectFilterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Filter"
    static let description = IntentDescription("Choose which saved smart filter the widget shows, or No Filter for all tasks.")

    @Parameter(title: "Filter", default: SmartFilterEntity.noFilter)
    var filter: SmartFilterEntity?

    init() {}

    init(filter: SmartFilterEntity?) {
        self.filter = filter
    }
}
