#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

// Renders iPhone-sized approximations of the iOS app's screens.
// Composed from the public LillistUI components plus inline mock chrome —
// the real RootShell/TodayView/SettingsTab live in the iOS app target
// and aren't reachable from this test bundle.
@MainActor
final class IOSScreenTourTests: XCTestCase {

    private let phoneSize = CGSize(width: 393, height: 852)   // iPhone 16 Pro logical size

    // MARK: - Sample data

    private func task(
        _ title: String,
        status: Status = .todo,
        deadline: Date? = nil
    ) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: UUID(), title: title, notes: "", status: status,
            start: nil, startHasTime: false,
            deadline: deadline, deadlineHasTime: deadline != nil,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_780_000_000),
            closedAt: status == .closed ? Date(timeIntervalSince1970: 1_780_000_000) : nil,
            deletedAt: nil
        )
    }

    private func taskRow(
        _ title: String,
        status: Status = .todo,
        deadline: Date? = nil,
        tags: [String] = []
    ) -> some View {
        TaskRowView(
            task: task(title, status: status, deadline: deadline),
            tagNames: tags,
            onStatusClick: {}, onStatusLongPress: {}
        )
    }

    // MARK: - Screens

    func test_01_today_light() {
        let view = tabScaffold(title: "Today", subtitle: "Tue · May 16", icon: "sun.max") {
            VStack(spacing: 0) {
                ForEach(Array(todayItems().enumerated()), id: \.offset) { _, item in
                    item
                    Divider().padding(.leading, 44)
                }
            }
        }
        assertScreen(view, name: "01-today-light", colorScheme: .light, size: phoneSize)
    }

    func test_02_today_dark() {
        let view = tabScaffold(title: "Today", subtitle: "Tue · May 16", icon: "sun.max") {
            VStack(spacing: 0) {
                ForEach(Array(todayItems().enumerated()), id: \.offset) { _, item in
                    item
                    Divider().padding(.leading, 44)
                }
            }
        }
        assertScreen(view, name: "02-today-dark", colorScheme: .dark, size: phoneSize)
    }

    func test_03_allTags_light() {
        let view = tabScaffold(title: "All", subtitle: "Tags", icon: "tag") {
            VStack(spacing: 0) {
                tagRow("work", count: 14, hex: "#3366FF")
                tagRow("errands", count: 6, hex: "#22AA66")
                tagRow("personal", count: 11, hex: "#FF6644")
                tagRow("reading", count: 4, hex: "#AA66FF")
                tagRow("urgent", count: 3, hex: "#EE3344")
                tagRow("ideas", count: 9, hex: "#FFB822")
                tagRow("watch-later", count: 2, hex: "#5566FF")
            }
        }
        assertScreen(view, name: "03-all-tags-light", colorScheme: .light, size: phoneSize)
    }

    func test_04_filters_light() {
        let view = tabScaffold(title: "Filters", subtitle: "Smart filters", icon: "line.3.horizontal.decrease.circle") {
            VStack(spacing: 0) {
                filterRow("Today", icon: "sun.max", badge: 6)
                filterRow("Upcoming", icon: "calendar", badge: 14)
                filterRow("Overdue", icon: "exclamationmark.triangle", badge: 2)
                filterRow("Inbox", icon: "tray", badge: 3)
                filterRow("Completed", icon: "checkmark.circle")
                filterRow("Blocked on me", icon: "hand.raised", badge: 1)
                filterRow("This week at work", icon: "briefcase", badge: 9)
            }
        }
        assertScreen(view, name: "04-filters-light", colorScheme: .light, size: phoneSize)
    }

    func test_05_search_light() {
        let view = tabScaffold(title: "Search", subtitle: "“launch”", icon: "magnifyingglass") {
            VStack(spacing: 0) {
                searchRow(title: "Draft launch email", subtitle: "Today · #work · started",
                          tint: "#3366FF")
                searchRow(title: "Pre-launch retrospective notes",
                          subtitle: "Journal · 3 days ago", tint: nil)
                searchRow(title: "Launch checklist v3", subtitle: "All Tasks · #work",
                          tint: "#3366FF")
                searchRow(title: "Ship 1.0 release", subtitle: "Overdue · #work · blocked",
                          tint: "#EE3344")
            }
        }
        assertScreen(view, name: "05-search-light", colorScheme: .light, size: phoneSize)
    }

    func test_06_taskDetail_light() {
        let view = ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                navBar(title: "Draft launch email", leading: "Today", trailing: "Edit")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            StatusIndicatorView(status: .started, onClick: {}, onLongPress: {})
                            Text("Draft launch email")
                                .font(.system(size: 22, weight: .semibold))
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            TagChipView(name: "work", tint: TagTint(hex: "#3366FF"))
                            TagChipView(name: "urgent", tint: TagTint(hex: "#FF6644"))
                            Label("May 22", systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        labelledSection(title: "NOTES") {
                            Text("Outline the customer announcement: highlight CloudKit sync, the new recurrence engine, and the iOS quick-capture share extension.")
                                .font(.system(size: 14))
                        }
                        Divider()
                        labelledSection(title: "SUBTASKS") {
                            VStack(spacing: 4) {
                                taskRow("Pull metrics from beta program", status: .closed)
                                taskRow("Draft hero paragraph", status: .started)
                                taskRow("Get screenshots from QA", status: .blocked,
                                        tags: ["urgent"])
                                taskRow("Schedule review with Alex")
                            }
                        }
                        Divider()
                        labelledSection(title: "JOURNAL") {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(.tertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("May 14, 9:14am")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                    Text("Got first draft to Alex for review. Waiting on the screenshots from QA before sending out broadly.")
                                        .font(.system(size: 13))
                                }
                            }
                        }
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
            }
            .frame(width: phoneSize.width, height: phoneSize.height)
            .background(Color(.systemBackground))

            FloatingAddButton(onTap: {})
                .padding(.trailing, 18)
                .padding(.bottom, 32)
        }
        assertScreen(view, name: "06-task-detail-light", colorScheme: .light, size: phoneSize)
    }

    func test_07_quickCaptureSheet_dark() {
        let view = ZStack(alignment: .bottom) {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 38, height: 5)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 12) {
                    Text("New task")
                        .font(.system(size: 17, weight: .semibold))
                    QuickCaptureField(
                        text: .constant("Buy lemons #errands ^tomorrow"),
                        tagSuggestions: ["errands", "shopping", "groceries"],
                        dateSuggestions: ["today", "tomorrow", "weekend"],
                        onSubmit: { _ in }
                    )
                    HStack {
                        Spacer()
                        Text("Save · ⏎")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        assertScreen(view, name: "07-quick-capture-sheet-dark", colorScheme: .dark, size: phoneSize)
    }

    func test_08_settings_light() {
        let view = VStack(spacing: 0) {
            navBar(title: "Settings", leading: nil, trailing: nil)
            ScrollView {
                VStack(spacing: 18) {
                    settingsGroup(title: "GENERAL") {
                        settingRow(label: "Default list", value: "Today")
                        settingRow(label: "First weekday", value: "Monday")
                        settingRow(label: "Show subtasks inline", value: "On")
                    }
                    settingsGroup(title: "NOTIFICATIONS") {
                        settingRow(label: "Notifications", value: "Enabled")
                        settingRow(label: "All-day reminder", value: "9:00 AM")
                        settingRow(label: "Snooze default", value: "1 hour")
                        settingRow(label: "Morning summary", value: "Weekdays")
                    }
                    settingsGroup(title: "QUICK CAPTURE") {
                        settingRow(label: "Share extension", value: "Enabled")
                        settingRow(label: "Default list", value: "Inbox")
                    }
                    settingsGroup(title: "CRASH REPORTING") {
                        settingRow(label: "Prompt after crashes", value: "On")
                        settingRow(label: "Include logs", value: "On")
                    }
                    settingsGroup(title: "ABOUT") {
                        settingRow(label: "Version", value: "1.0 (42)")
                        settingRow(label: "iCloud", value: "Synced just now")
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        .background(Color(.systemGroupedBackground))
        assertScreen(view, name: "08-settings-light", colorScheme: .light, size: phoneSize)
    }

    func test_09_onboarding_light() {
        let view = VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(.tint)
                Text("Welcome to Lillist")
                    .font(.system(size: 30, weight: .semibold))
                Text("Your tasks, projects, and journal — synced across every Apple device with iCloud.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            VStack(alignment: .leading, spacing: 14) {
                onboardingBullet(icon: "sparkles", title: "Five smart filters",
                                 message: "Today, Upcoming, Overdue, Inbox, Completed — ready out of the box.")
                onboardingBullet(icon: "bell.badge", title: "Notifications when you ask",
                                 message: "Reminders fire only after you opt in — Lillist won't pester.")
                onboardingBullet(icon: "icloud", title: "Private CloudKit sync",
                                 message: "Your data stays inside your iCloud account. No third-party servers.")
            }
            .padding(.horizontal, 28)
            Spacer()
            VStack(spacing: 10) {
                Button(action: {}) {
                    Text("Set up notifications")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Button("Maybe later", action: {})
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        .background(Color(.systemBackground))
        assertScreen(view, name: "09-onboarding-light", colorScheme: .light, size: phoneSize)
    }

    func test_10_iCloudRequired_light() {
        let view = VStack(spacing: 24) {
            Spacer()
            Image(systemName: "icloud.slash")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.secondary)
            Text("iCloud is required")
                .font(.system(size: 24, weight: .semibold))
            Text("Lillist stores everything in your private iCloud database. Sign in to iCloud in Settings to get started.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: {}) {
                Text("Open Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        .background(Color(.systemBackground))
        assertScreen(view, name: "10-icloud-required-light", colorScheme: .light, size: phoneSize)
    }

    // MARK: - Sample composition helpers

    private func todayItems() -> [AnyView] {
        [
            AnyView(taskRow("Buy milk", tags: ["errands"])),
            AnyView(taskRow("Draft launch email", status: .started,
                            tags: ["work", "urgent"])),
            AnyView(taskRow("Ship 1.0 release", status: .blocked,
                            deadline: Date(timeIntervalSince1970: 1_780_300_000),
                            tags: ["work"])),
            AnyView(taskRow("Reply to investors", tags: ["work"])),
            AnyView(taskRow("Sync with design", status: .started, tags: ["work"])),
            AnyView(taskRow("Pay rent", status: .closed)),
            AnyView(taskRow("Renew domain", tags: ["personal"])),
            AnyView(taskRow("Read DDIA ch. 6", tags: ["reading"]))
        ]
    }

    @ViewBuilder
    private func tabScaffold<C: View>(
        title: String, subtitle: String, icon: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                navBar(title: title, subtitle: subtitle, leading: nil, trailing: nil)
                ScrollView { content().padding(.top, 4) }
                tabBar(active: title)
            }
            .frame(width: phoneSize.width, height: phoneSize.height)
            .background(Color(.systemBackground))

            FloatingAddButton(onTap: {})
                .padding(.trailing, 18)
                .padding(.bottom, 88)
        }
    }

    @ViewBuilder
    private func navBar(title: String, subtitle: String? = nil,
                        leading: String?, trailing: String?) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let leading {
                    Text(leading)
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                } else {
                    Spacer().frame(width: 60)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                } else {
                    Spacer().frame(width: 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func tabBar(active: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                tabItem("Today", icon: "sun.max", active: active == "Today")
                tabItem("All", icon: "tag", active: active == "All")
                tabItem("Filters", icon: "line.3.horizontal.decrease.circle",
                        active: active == "Filters")
                tabItem("Search", icon: "magnifyingglass", active: active == "Search")
                tabItem("Settings", icon: "gearshape", active: active == "Settings")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func tabItem(_ label: String, icon: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 18))
            Text(label).font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
    }

    @ViewBuilder
    private func tagRow(_ name: String, count: Int, hex: String) -> some View {
        let color = (TagTint(hex: hex)?.resolved(in: .light).color) ?? Color.gray
        HStack(spacing: 10) {
            Circle().fill(color)
                .frame(width: 10, height: 10)
            Text(name).font(.system(size: 16))
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Divider().offset(y: 20), alignment: .bottom)
    }

    @ViewBuilder
    private func filterRow(_ name: String, icon: String, badge: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(name).font(.system(size: 16))
            Spacer()
            if let badge {
                Text("\(badge)")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Divider().offset(y: 20), alignment: .bottom)
    }

    @ViewBuilder
    private func searchRow(title: String, subtitle: String, tint: String?) -> some View {
        let bar = (tint.flatMap { TagTint(hex: $0)?.resolved(in: .light).color }) ?? Color.secondary
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(bar)
                .frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Divider().offset(y: 24), alignment: .bottom)
    }

    @ViewBuilder
    private func labelledSection<Body: View>(title: String,
                                             @ViewBuilder _ body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            body()
        }
    }

    @ViewBuilder
    private func settingsGroup<Body: View>(title: String,
                                           @ViewBuilder _ body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { body() }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func settingRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15))
            Spacer()
            Text(value).font(.system(size: 14)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Divider().offset(y: 18).padding(.leading, 14), alignment: .bottom)
    }

    @ViewBuilder
    private func onboardingBullet(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Assertion

    private func assertScreen<V: View>(
        _ view: V,
        name: String,
        colorScheme: ColorScheme,
        size: CGSize,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let host = UIHostingController(rootView:
            view.environment(\.colorScheme, colorScheme)
                .environment(\.locale, Locale(identifier: "en_US"))
        )
        host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
            UITraitCollection(displayScale: 2)
        ])
        assertSnapshot(
            of: host,
            as: .image(size: size, traits: traits),
            named: name,
            fileID: fileID, file: filePath, testName: testName, line: line, column: column
        )
    }
}
#endif
