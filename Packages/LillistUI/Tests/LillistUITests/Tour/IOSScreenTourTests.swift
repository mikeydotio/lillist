#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

// Renders iPhone-sized approximations of the iOS app's screens after
// the 3-tab restructure. The five Tab-era screens (Today, All, Filters,
// Search, AllTags) collapsed into a single primary `TasksScreen` with
// an expanding filter header, sort menu, outline list, and trailing-
// only delete swipe. The TaskDetail, QuickCapture, Onboarding, and
// iCloud-required screens remain as parallel surfaces and keep their
// inline-composed snapshots from the previous suite.
@MainActor
final class IOSScreenTourTests: RecordableSnapshotTestCase {

    private let phoneSize = CGSize(width: 393, height: 852)   // iPhone 16 Pro logical size

    // MARK: - Sample data

    private func task(
        _ title: String,
        id: UUID = UUID(),
        parent: UUID? = nil,
        status: Status = .todo,
        deadline: Date? = nil,
        modifiedAt: Date? = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id, title: title, notes: "", status: status,
            start: nil, startHasTime: false,
            deadline: deadline, deadlineHasTime: deadline != nil,
            position: 0, isPinned: false, parentID: parent,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            modifiedAt: modifiedAt,
            closedAt: status == .closed ? Date(timeIntervalSince1970: 1_780_000_000) : nil,
            deletedAt: nil
        )
    }

    private func node(_ record: TaskStore.TaskRecord,
                      tagNames: [String] = [],
                      children: [TaskNode] = []) -> TaskNode {
        TaskNode(record: record, tagNames: tagNames, children: children)
    }

    private func sampleRoots() -> [TaskNode] {
        let shipID = UUID()
        let shipNode = node(
            task("Ship 1.0 release", id: shipID, status: .blocked,
                 deadline: Date(timeIntervalSince1970: 1_780_300_000)),
            children: [
                node(task("Pull metrics from beta", parent: shipID, status: .closed)),
                node(task("Draft hero paragraph", parent: shipID, status: .started)),
                node(task("Get screenshots from QA", parent: shipID, status: .blocked))
            ]
        )
        return [
            node(task("Buy milk")),
            node(task("Draft launch email", status: .started)),
            shipNode,
            node(task("Reply to investors")),
            node(task("Sync with design", status: .started)),
            node(task("Renew domain")),
            node(task("Read DDIA ch. 6"))
        ]
    }

    private func savedFilterChips() -> [SavedFilterChipSpec] {
        [
            SavedFilterChipSpec(id: UUID(), title: "Inbox"),
            SavedFilterChipSpec(id: UUID(), title: "Upcoming")
        ]
    }

    // MARK: - TasksScreen states

    func test_01_tasks_default_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "01-tasks-default-light", colorScheme: .light, size: phoneSize)
    }

    func test_02_tasks_default_dark() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "02-tasks-default-dark", colorScheme: .dark, size: phoneSize)
    }

    func test_03_tasks_filter_expanded_today_token_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(true),
                searchText: .constant("ship"),
                selectedTokens: .constant([.today]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "03-tasks-filter-expanded-light", colorScheme: .light, size: phoneSize)
    }

    func test_04_tasks_sort_due_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),                buildVersion: "0.1.0 (16)",
                sort: .constant(.due),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "04-tasks-sort-due-light", colorScheme: .light, size: phoneSize)
    }

    /// Closed root tasks are now visible in the default list — the
    /// pull-to-refresh "archive" gesture is what hides them. This
    /// snapshot guards the new "completed stays in place" UX.
    func test_11_tasks_completed_rows_visible_light() {
        var roots = sampleRoots()
        roots.append(node(task("Buy milk", status: .closed)))
        roots.append(node(task("Read DDIA ch. 6", status: .closed)))
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: roots,                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "11-tasks-completed-rows-visible-light",
                     colorScheme: .light, size: phoneSize)
    }

    /// "21 tasks archived. Tap to undo." banner pinned to the bottom
    /// after a pull-to-refresh archive sweep. The `reduceTransparencyOverride`
    /// is set so the toast's `accessibleMaterial` paints its opaque
    /// fallback — system materials don't render in the headless test
    /// host, leaving the capsule invisible without this override.
    func test_12_tasks_archive_toast_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                isArchiveToastPresented: .constant(true),
                savedFilters: savedFilterChips(),
                archivedCount: 21,
                dragController: DragController()
            )
        }
        .environment(\.reduceTransparencyOverride, true)
        assertScreen(view, name: "12-tasks-archive-toast-light",
                     colorScheme: .light, size: phoneSize)
    }

    /// Snapshot showing `TasksScreen` with an in-progress `.between` drag:
    /// the phantom "Reply to investors" row appears near "Sync with design",
    /// with a top-level drop divider just below it. The source row at index 3
    /// is invisible (opacity 0) while dragging.
    func test_13_tasks_mid_drag_light() {
        let controller = DragController(onDrop: { _, _ in })
        let roots = sampleRoots()

        // roots[3] = "Reply to investors", roots[4] = "Sync with design"
        let draggedID = roots[3].record.id
        let targetID  = roots[4].record.id

        controller.flatRows = roots.map {
            DragReorderRow(id: $0.record.id, parentID: nil, depth: 0)
        }
        // Synthetic geometry matching the list rendering order.
        var y: CGFloat = 100
        for root in roots {
            controller.geometry[root.record.id] = CGRect(
                x: 12, y: y, width: 369, height: 44
            )
            y += 50
        }
        controller.beginDrag(
            rowID: draggedID,
            originalHeight: 44,
            cursorY: controller.geometry[targetID]?.midY ?? 250
        )
        controller.setResolvedTarget(
            .between(beforeID: nil, afterID: targetID, parentID: nil)
        )

        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: roots,                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: controller
            )
        }
        assertScreen(view, name: "13-tasks-mid-drag-light", colorScheme: .light, size: phoneSize)
    }

    // NOTE: The empty-state snapshot (`TasksScreen` with `roots: []`) moved
    // to `Lillist-iOSAppHostedTests/GlassSnapshotTests`. Its body is
    // `RainbowEmptyStateView`, whose `DotGridBackdrop` composites through
    // `.drawingGroup()` (Metal) — which, like Liquid Glass, does NOT render
    // in the offscreen `CALayer.render(in:)` capture (it blanks the whole
    // empty-state subtree). See docs/engineering-notes.md 2026-06-15.

    /// A mock Settings landing row mirroring `SettingsTab`'s drill-down
    /// rows: a wayfinding `SettingsRowIcon` tile + title pushing a
    /// (dummy) destination within the screen's navigation stack.
    @ViewBuilder
    private func settingsNavRow(_ title: String, _ systemImage: String, _ tint: Color) -> some View {
        NavigationLink {
            EmptyView()
        } label: {
            Label {
                Text(title)
            } icon: {
                SettingsRowIcon(systemImage: systemImage, tint: tint)
            }
        }
    }

    func test_08_settings_light() {
        // The icon-row landing screen (Plan: Settings sub-pages). Each row
        // carries a fixed RainbowPalette wayfinding hue and drills into a
        // focused sub-page (rendered for real in the app target).
        let view = SettingsScreen(onDone: {}) {
            Section {
                settingsNavRow("Appearance", "paintpalette.fill", RainbowPalette.scriptPurple.base)
                settingsNavRow("Task Defaults", "checklist", RainbowPalette.focusBlue.base)
                settingsNavRow("Notifications", "bell.badge.fill", RainbowPalette.cautionAmber.base)
                settingsNavRow("iCloud Sync", "icloud.fill", RainbowPalette.Spectrum.cyan)
                settingsNavRow("Quick Capture", "bolt.fill", RainbowPalette.actionOrange.base)
                settingsNavRow("Data Management", "externaldrive.fill", RainbowPalette.growthGreen.base)
                settingsNavRow("Debug", "ladybug.fill", LillistColor.textMuted)
            }
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        // SettingsScreen renders a SwiftUI Form, whose per-section AA drift
        // breaches exact-pixel on cold-cache renders (see engineering-notes
        // 2026-05-17 "Form views drift on cold-cache runs"). Relax this one
        // tour snapshot to the Form precision pair; all other tour snapshots
        // stay exact-pixel so they keep catching real regressions.
        assertScreen(view, name: "08-settings-light", colorScheme: .light,
                     size: phoneSize, precision: 0.99, perceptualPrecision: 0.98)
    }

    func test_08b_settingsDetail_light() {
        // A drill-down sub-page (`SettingsDetailScreen`) — the shared chrome
        // reused by every Settings sub-page. Wrapped in a NavigationStack so
        // the inline title renders, mirroring how it's pushed at runtime.
        let view = NavigationStack {
            SettingsDetailScreen("Appearance") {
                Section {
                    settingRow(label: "Default tag tint", value: "Purple")
                } footer: {
                    Text("Applied to new tags. Existing tags keep their custom color.")
                }
            }
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        assertScreen(view, name: "08b-settings-detail-light", colorScheme: .light,
                     size: phoneSize, precision: 0.99, perceptualPrecision: 0.98)
    }

    // MARK: - Non-Tasks screens (inline-composed)

    /// The compact detail card (issue #8): status glyph + inline title + pin,
    /// a description box, tag chips with a "+ Tag" pill, and the three drill-in
    /// summary lines (schedule / attachments / journal). The display-only
    /// `StatusCubeView` stands in for the interactive `StatusIndicatorView`,
    /// whose `Menu` hit layer blanks the offscreen capture (see
    /// docs/engineering-notes.md 2026-06-12 + the 2026-06-14 refinement); the
    /// real card is captured app-hosted in
    /// `Lillist-iOSAppHostedTests/GlassSnapshotTests`.
    func test_06_taskDetail_light() {
        let card = VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                StatusCubeView(status: .started)
                    .frame(width: 44, height: 44)
                Text("Draft launch email")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LillistColor.textStrong)
                Spacer(minLength: 8)
                Image(systemName: "pin.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(RainbowPalette.scriptPurple.base)
            }
            Text("Outline the customer announcement: highlight CloudKit sync, the new recurrence engine, and the iOS quick-capture share extension.")
                .font(.system(size: 14))
                .foregroundStyle(LillistColor.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.rainbowWell)
                )
            HStack(spacing: 6) {
                TagChipView(name: "work", tint: TagTint(hex: "#3366FF"))
                TagChipView(name: "urgent", tint: TagTint(hex: "#FF6644"))
                detailTagAddPill()
            }
            VStack(alignment: .leading, spacing: 12) {
                detailSummaryRow(icon: "calendar", text: "Due tomorrow at 5 PM (Every week)", pill: "EDIT")
                detailSummaryRow(icon: "paperclip", text: "2 attachments", pill: "ADD")
                detailSummaryRow(icon: "book.closed", text: "1 journal entry", pill: nil)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LillistColor.card)
        )
        .padding(.horizontal, 16)

        let view = ZStack {
            LillistColor.workspace
            card
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        assertScreen(view, name: "06-task-detail-light", colorScheme: .light, size: phoneSize)
    }

    /// The dashed "+ Tag" pill mirrored from `TagAssignmentField`.
    private func detailTagAddPill() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.caption)
            Text("Tag").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(RainbowPalette.scriptPurple.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlay(
            Capsule().strokeBorder(
                RainbowPalette.scriptPurple.base.opacity(0.55),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        )
    }

    /// One drill-in summary line: icon + text + a trailing action pill or
    /// chevron (mirrors `TaskEditorView.drillRow`).
    private func detailSummaryRow(icon: String, text: String, pill: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(LillistColor.textMuted)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(LillistColor.textBody)
            Spacer(minLength: 8)
            if let pill {
                Text(pill)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(RainbowPalette.scriptPurple.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(RainbowPalette.scriptPurple.base.opacity(0.5), lineWidth: 1))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(LillistColor.textFaint)
            }
        }
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

    func test_11_diagnosticsIncludeSheet_light() {
        let view = DiagnosticsIncludeSheet(
            includeLogs: .constant(true),
            includeStore: .constant(false),
            onCreate: {},
            onCancel: {}
        )
        .frame(width: phoneSize.width, height: phoneSize.height)
        assertScreen(view, name: "11-diagnostics-include-sheet-light", colorScheme: .light, size: phoneSize)
    }

    // MARK: - Shell helper

    /// Wraps a migrated screen in a NavigationStack, sized to the iPhone
    /// tour viewport.
    ///
    /// The `FloatingAddButton` the real shell paints is intentionally
    /// NOT overlaid here: it is Liquid Glass, which blanks the entire
    /// offscreen snapshot (see docs/engineering-notes.md 2026-06-12), so
    /// it is covered in `Lillist-iOSAppHostedTests/GlassSnapshotTests`
    /// instead. This tour verifies screen *composition* (rows, chips,
    /// layout). The `fab` flag is retained at call sites to document
    /// which screens carry one in the real shell.
    @ViewBuilder
    private func phoneShell<C: View>(
        fab: Bool,
        @ViewBuilder content: () -> C
    ) -> some View {
        NavigationStack { content() }
            .frame(width: phoneSize.width, height: phoneSize.height)
            .background(Color(.systemBackground))
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
        precision: Float = 1,
        perceptualPrecision: Float = 1,
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
        let traits = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            mutableTraits.displayScale = 2
        }
        assertSnapshot(
            of: host,
            as: .image(precision: precision,
                       perceptualPrecision: perceptualPrecision,
                       size: size,
                       traits: traits),
            named: name,
            fileID: fileID, file: filePath, testName: testName, line: line, column: column
        )
    }
}
#endif
