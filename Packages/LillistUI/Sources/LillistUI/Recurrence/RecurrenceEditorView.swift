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
                    Section("Frequency") {
                        Picker("Frequency", selection: $viewModel.freq) {
                            Text("Daily").tag(RecurrenceRule.Frequency.daily)
                            Text("Weekly").tag(RecurrenceRule.Frequency.weekly)
                            Text("Monthly").tag(RecurrenceRule.Frequency.monthly)
                            Text("Yearly").tag(RecurrenceRule.Frequency.yearly)
                        }
                        Stepper("Every \(viewModel.interval)", value: $viewModel.interval, in: 1...365)
                    }

                    if viewModel.freq == .weekly {
                        Section("On days") {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                Toggle(label(for: day), isOn: bindingFor(day: day, in: $viewModel.byDay))
                            }
                        }
                    }

                    if viewModel.freq == .monthly {
                        Section("On days of month") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                                      spacing: 6) {
                                ForEach(1...31, id: \.self) { day in
                                    dayCell(day)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section("Limit") {
                        Stepper(viewModel.count.map { "After \($0) occurrences" } ?? "No occurrence limit",
                                value: Binding(
                                    get: { viewModel.count ?? 0 },
                                    set: { viewModel.count = $0 == 0 ? nil : $0 }
                                ),
                                in: 0...365)
                        Toggle("End by date", isOn: Binding(
                            get: { viewModel.until != nil },
                            set: { on in viewModel.until = on ? (viewModel.until ?? Date().addingTimeInterval(86_400 * 30)) : nil }
                        ))
                        if let _ = viewModel.until {
                            DatePicker("End date", selection: Binding(
                                get: { viewModel.until ?? Date() },
                                set: { viewModel.until = $0 }
                            ), displayedComponents: [.date])
                        }
                    }
                } else {
                    Section("Repeat after") {
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
                        .fill(isSelected ? Color.accentColor : Color.clear)
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Day \(day) selected" : "Day \(day) not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
