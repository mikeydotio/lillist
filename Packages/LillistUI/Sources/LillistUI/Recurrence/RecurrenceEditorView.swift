import SwiftUI
import LillistCore

/// SwiftUI editor for a `RecurrenceRule`. Bind to a
/// `RecurrenceEditorViewModel` and call `onCommit` when the user accepts.
/// Used by the macOS detail view and the iOS RecurrenceSheet.
///
/// Plan 11 brings this editor into v1; design Section 10 originally
/// scheduled it for v2 but the implementation was pulled forward.
public struct RecurrenceEditorView: View {
    @Binding var viewModel: RecurrenceEditorViewModel
    public var onCommit: ((RecurrenceRule?) -> Void)?
    public var onCancel: (() -> Void)?

    public init(
        viewModel: Binding<RecurrenceEditorViewModel>,
        onCommit: ((RecurrenceRule?) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self._viewModel = viewModel
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Repeats", isOn: $viewModel.repeats)
            }

            if viewModel.repeats {
                Section {
                    Picker("Schedule", selection: $viewModel.mode) {
                        Text("Repeat").tag(RecurrenceEditorViewModel.Mode.calendar)
                        Text("When completed").tag(RecurrenceEditorViewModel.Mode.afterCompletion)
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.mode == .calendar {
                    Section(header: Text("Frequency").accessibilityAddTraits(.isHeader)) {
                        Picker("Frequency", selection: $viewModel.freq) {
                            Text("Daily").tag(RecurrenceRule.Frequency.daily)
                            Text("Weekly").tag(RecurrenceRule.Frequency.weekly)
                            Text("Monthly").tag(RecurrenceRule.Frequency.monthly)
                            Text("Yearly").tag(RecurrenceRule.Frequency.yearly)
                        }
                        HStack {
                            Stepper("Every", value: $viewModel.interval, in: 1...365)
                            TextField(
                                "Interval",
                                value: $viewModel.interval,
                                format: .number.precision(.integerLength(1...3))
                            )
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .accessibilityLabel(String(localized: "Interval, every N units", bundle: .module))
                        }
                    }

                    if viewModel.freq == .weekly {
                        Section(header: Text("On days").accessibilityAddTraits(.isHeader)) {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                Toggle(label(for: day), isOn: bindingFor(day: day, in: $viewModel.byDay))
                            }
                        }
                    }

                    if viewModel.freq == .monthly {
                        Section(header: Text("On days of month").accessibilityAddTraits(.isHeader)) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                                      spacing: 6) {
                                ForEach(1...31, id: \.self) { day in
                                    dayCell(day)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section(header: Text("Limit").accessibilityAddTraits(.isHeader)) {
                        Toggle("Repeat forever", isOn: Binding(
                            get: { viewModel.count == nil },
                            set: { isUnbounded in
                                if isUnbounded {
                                    viewModel.count = nil
                                } else {
                                    viewModel.count = viewModel.count ?? 10
                                }
                            }
                        ))
                        if let bound = viewModel.count {
                            Stepper("After \(bound) occurrence\(bound == 1 ? "" : "s")",
                                    value: Binding(
                                        get: { bound },
                                        set: { viewModel.count = $0 }
                                    ),
                                    in: 1...365)
                        }
                        Toggle("End by date", isOn: Binding(
                            get: { viewModel.until != nil },
                            set: { on in viewModel.until = on ? (viewModel.until ?? defaultUntil()) : nil }
                        ))
                        if let _ = viewModel.until {
                            DatePicker("End date", selection: Binding(
                                get: { viewModel.until ?? Date() },
                                set: { viewModel.until = $0 }
                            ), displayedComponents: [.date])
                        }
                    }
                } else {
                    Section(header: Text("Repeat after").accessibilityAddTraits(.isHeader)) {
                        Picker("Repeat after", selection: $viewModel.afterCompletionSeconds) {
                            Text("1 day").tag(TimeInterval(86_400))
                            Text("3 days").tag(TimeInterval(86_400 * 3))
                            Text("1 week").tag(TimeInterval(86_400 * 7))
                            Text("2 weeks").tag(TimeInterval(86_400 * 14))
                            Text("1 month (~30d)").tag(TimeInterval(86_400 * 30))
                        }
                    }
                }
            }

            if onCommit != nil || onCancel != nil {
                Section {
                    HStack {
                        if let onCancel {
                            Button("Cancel", role: .cancel, action: onCancel)
                                .keyboardShortcut(.cancelAction)
                        }
                        Spacer()
                        if let onCommit {
                            Button("Save") { onCommit(viewModel.build()) }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
        }
    }

    private func label(for day: Weekday) -> String {
        let index = Self.index(for: day)
        // `standaloneWeekdaySymbols` is always Sunday-first; matches our
        // Weekday raw indexing. Returns the system-localized form
        // ("Sunday" in en, "Sonntag" in de, "الأحد" in ar).
        let symbols = Calendar.current.standaloneWeekdaySymbols
        guard symbols.indices.contains(index) else {
            return String(localized: defaultEnglishName(for: day), bundle: .module)
        }
        return symbols[index]
    }

    private static func index(for day: Weekday) -> Int {
        switch day {
        case .sunday:    return 0
        case .monday:    return 1
        case .tuesday:   return 2
        case .wednesday: return 3
        case .thursday:  return 4
        case .friday:    return 5
        case .saturday:  return 6
        }
    }

    private func defaultEnglishName(for day: Weekday) -> String.LocalizationValue {
        switch day {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    private func bindingFor(day: Weekday, in set: Binding<Set<Weekday>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(day) },
            set: { isOn in
                var copy = set.wrappedValue
                if isOn { copy.insert(day) } else { copy.remove(day) }
                set.wrappedValue = copy
            }
        )
    }

    private func bindingFor(monthDay d: Int, in set: Binding<Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(d) },
            set: { isOn in
                var copy = set.wrappedValue
                if isOn { copy.insert(d) } else { copy.remove(d) }
                set.wrappedValue = copy
            }
        )
    }

    /// Sensible default end-date when the user flips the "End by date"
    /// toggle on (Plan 23). Computes a date a frequency-appropriate
    /// distance from the task's anchor (start or deadline) so a task
    /// scheduled six months out doesn't get a default end-date 30 days
    /// from *today*. Defaults: daily → 30 days, weekly → 12 weeks
    /// (~3 months), monthly → 6 months, yearly → 3 years, all scaled
    /// by `interval`.
    private func defaultUntil() -> Date {
        let anchor = viewModel.taskAnchorDate ?? Date()
        let units: Int
        let component: Calendar.Component
        switch viewModel.freq {
        case .daily:   units = 30 * max(1, viewModel.interval); component = .day
        case .weekly:  units = 12 * max(1, viewModel.interval); component = .weekOfYear
        case .monthly: units = 6 * max(1, viewModel.interval);  component = .month
        case .yearly:  units = 3 * max(1, viewModel.interval);  component = .year
        }
        return Calendar.current.date(byAdding: component, value: units, to: anchor) ?? anchor
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let isSelected = viewModel.byMonthDay.contains(day)
        Button {
            if isSelected {
                viewModel.byMonthDay.remove(day)
            } else {
                viewModel.byMonthDay.insert(day)
            }
        } label: {
            Text("\(day)")
                .font(.body)
                .frame(minWidth: 36, minHeight: 36)
                .background {
                    Circle()
                        .fill(isSelected ? RainbowPalette.focusBlue.base : Color.clear)
                }
                .overlay {
                    if isSelected {
                        RainbowTopHighlight(shape: Circle(), strength: 0.4)
                    }
                }
                .foregroundStyle(isSelected ? Color.white : LillistColor.textBody)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected
            ? String(localized: "Day \(day) selected", bundle: .module)
            : String(localized: "Day \(day) not selected", bundle: .module))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
