#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

// Renders iPhone-sized approximations of the iOS app's screens.
// Plan 20a Task 4f: the five Tab screens (Today, All, Filters, Search,
// Settings) now render the real `LillistUI.*Screen` structs wrapped in
// a NavigationStack — no more inline mock chrome for those. The
// remaining tests (TaskDetail, QuickCapture dialog, Onboarding, iCloud
// gate) still compose inline because they cover surfaces Plan 20a
// did not migrate.
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
            onStatusClick: {}, onStatusSet: { _ in }
        )
    }

    private func todayRecords() -> [TaskStore.TaskRecord] {
        [
            task("Buy milk"),
            task("Draft launch email", status: .started),
            task("Ship 1.0 release", status: .blocked,
                 deadline: Date(timeIntervalSince1970: 1_780_300_000)),
            task("Reply to investors"),
            task("Sync with design", status: .started),
            task("Pay rent", status: .closed),
            task("Renew domain"),
            task("Read DDIA ch. 6")
        ]
    }

    private func filterRecord(
        _ name: String, isPinned: Bool, position: Double
    ) -> SmartFilterStore.SmartFilterRecord {
        SmartFilterStore.SmartFilterRecord(
            id: UUID(),
            name: name,
            group: PredicateGroup(combinator: .all, predicates: []),
            tintColor: nil,
            sortField: .manualPosition,
            sortAscending: true,
            isPinned: isPinned,
            position: position,
            createdAt: nil,
            modifiedAt: nil
        )
    }

    // MARK: - Migrated Tab screens (Plan 20a)

    func test_01_today_light() {
        let view = phoneShell(fab: true) {
            TodayScreen(
                results: todayRecords(),
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)"
            )
        }
        assertScreen(view, name: "01-today-light", colorScheme: .light, size: phoneSize)
    }

    func test_02_today_dark() {
        let view = phoneShell(fab: true) {
            TodayScreen(
                results: todayRecords(),
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)"
            )
        }
        assertScreen(view, name: "02-today-dark", colorScheme: .dark, size: phoneSize)
    }

    func test_03_allTags_light() {
        let tree: [AllTagsScreen.TagNode] = [
            .init(id: UUID(), name: "work"),
            .init(id: UUID(), name: "errands"),
            .init(id: UUID(), name: "personal"),
            .init(id: UUID(), name: "reading"),
            .init(id: UUID(), name: "urgent"),
            .init(id: UUID(), name: "ideas"),
            .init(id: UUID(), name: "watch-later")
        ]
        let view = phoneShell(fab: true) {
            AllTagsScreen(tree: tree)
        }
        assertScreen(view, name: "03-all-tags-light", colorScheme: .light, size: phoneSize)
    }

    func test_04_filters_light() {
        let pinned = [filterRecord("Today", isPinned: true, position: 0)]
        let others = [
            filterRecord("Upcoming", isPinned: false, position: 1),
            filterRecord("Overdue", isPinned: false, position: 2),
            filterRecord("Inbox", isPinned: false, position: 3),
            filterRecord("Completed", isPinned: false, position: 4),
            filterRecord("Blocked on me", isPinned: false, position: 5),
            filterRecord("This week at work", isPinned: false, position: 6)
        ]
        let view = phoneShell(fab: true) {
            FiltersListScreen(pinned: pinned, others: others)
        }
        assertScreen(view, name: "04-filters-light", colorScheme: .light, size: phoneSize)
    }

    func test_05_search_light() {
        let view = phoneShell(fab: true) {
            SearchScreen(
                query: .constant("launch"),
                scope: .constant(.all),
                results: [
                    task("Draft launch email", status: .started),
                    task("Pre-launch retrospective notes"),
                    task("Launch checklist v3"),
                    task("Ship 1.0 release", status: .blocked,
                         deadline: Date(timeIntervalSince1970: 1_780_300_000))
                ],
                recents: []
            )
        }
        assertScreen(view, name: "05-search-light", colorScheme: .light, size: phoneSize)
    }

    func test_08_settings_light() {
        let view = SettingsScreen(onDone: {}) {
            Section("GENERAL") {
                settingRow(label: "Default list", value: "Today")
                settingRow(label: "First weekday", value: "Monday")
                settingRow(label: "Show subtasks inline", value: "On")
            }
            Section("NOTIFICATIONS") {
                settingRow(label: "Notifications", value: "Enabled")
                settingRow(label: "All-day reminder", value: "9:00 AM")
                settingRow(label: "Snooze default", value: "1 hour")
                settingRow(label: "Morning summary", value: "Weekdays")
            }
            Section("QUICK CAPTURE") {
                settingRow(label: "Share extension", value: "Enabled")
                settingRow(label: "Default list", value: "Inbox")
            }
            Section("CRASH REPORTING") {
                settingRow(label: "Prompt after crashes", value: "On")
                settingRow(label: "Include logs", value: "On")
            }
            Section("ABOUT") {
                settingRow(label: "Version", value: "1.0 (42)")
                settingRow(label: "iCloud", value: "Synced just now")
            }
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        assertScreen(view, name: "08-settings-light", colorScheme: .light, size: phoneSize)
    }

    // MARK: - Non-Tab screens (kept inline — out of Plan 20a scope)

    func test_06_taskDetail_light() {
        let view = ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                detailNavBar(title: "Draft launch email", leading: "Today", trailing: "Edit")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            StatusIndicatorView(status: .started, onClick: {}, onSetStatus: { _ in })
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

    func test_07_quickCaptureDialog_dark() {
        let view = ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea()
            QuickCaptureDialog(
                text: .constant("Buy lemons #errands ^tomorrow"),
                onSubmit: {}
            )
            .padding(.top, 80)
            .padding(.horizontal, 24)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        assertScreen(view, name: "07-quick-capture-dialog-dark", colorScheme: .dark, size: phoneSize)
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

    // MARK: - Shell helper (Plan 20a)

    /// Wraps a migrated Tab screen in a NavigationStack, sized to the
    /// iPhone tour viewport, with the FloatingAddButton overlay the
    /// real iOS shell paints.
    @ViewBuilder
    private func phoneShell<C: View>(
        fab: Bool,
        @ViewBuilder content: () -> C
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack { content() }
                .frame(width: phoneSize.width, height: phoneSize.height)
                .background(Color(.systemBackground))

            if fab {
                FloatingAddButton(onTap: {})
                    .padding(.trailing, 18)
                    .padding(.bottom, 88)
            }
        }
    }

    // MARK: - Mock chrome retained for test_06 / test_09 only

    @ViewBuilder
    private func detailNavBar(title: String,
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
                Text(title).font(.system(size: 17, weight: .semibold))
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
    private func labelledSection<Body: View>(title: String,
                                             @ViewBuilder _ body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            body()
        }
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

    // MARK: - Settings row mock (test_08 only)

    @ViewBuilder
    private func settingRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
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
