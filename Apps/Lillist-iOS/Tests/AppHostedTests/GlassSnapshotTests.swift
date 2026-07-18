import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
import LillistUI

/// App-hosted snapshot regression for the Rainbow Glass surfaces — the
/// FAB (lavender glass, matching the Quick Capture "Add task" button),
/// buttons, and toggles — and for the two iOS controls that blank the
/// *offscreen* `LillistUITests` capture and therefore must render here:
///   - the `QuickCaptureDialog` (`.panel` glass), and
///   - `StatusIndicatorView` (a `Menu` hit layer — the Menu, not glass,
///     is what blanks offscreen; see the 2026-06-14 refinement).
///
/// Liquid Glass only composites in a live key window, so glass snapshots
/// MUST run here — this bundle is app-hosted, so
/// `drawHierarchyInKeyWindow: true` renders through the simulator's live
/// window. The standalone `LillistUITests` bundle cannot capture glass
/// (it blanks the whole image); see docs/engineering-notes.md 2026-06-12.
///
/// Re-record after an intentional glass change:
///   xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
///     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
///     -only-testing:Lillist-iOSAppHostedTests/GlassSnapshotTests \
///     RECORD_SNAPSHOTS=YES
final class GlassSnapshotTests: XCTestCase {
    private var recordMode: SnapshotTestingConfiguration.Record {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : .missing
    }

    /// Guards the capture path itself: if a toolchain change ever stops
    /// glass compositing in app-hosted snapshots, this blanks and fails
    /// loudly, instead of silently weakening every other glass baseline.
    @MainActor
    func test_glassCaptureStillWorks() {
        let view = ZStack {
            backdrop
            Circle().fill(.clear).frame(width: 80, height: 80)
                .glassEffect(.regular.tint(.purple).interactive(), in: Circle())
        }
        snapshot(view, size: CGSize(width: 220, height: 180), dark: false)
    }

    @MainActor func test_fab_light() { snapshot(fab, size: fabSize, dark: false) }
    @MainActor func test_fab_dark()  { snapshot(fab, size: fabSize, dark: true) }

    @MainActor func test_buttons_light() { snapshot(buttonGallery, size: buttonsSize, dark: false) }
    @MainActor func test_buttons_dark()  { snapshot(buttonGallery, size: buttonsSize, dark: true) }

    @MainActor func test_toggles_light() { snapshot(toggleGallery, size: togglesSize, dark: false) }
    @MainActor func test_toggles_dark()  { snapshot(toggleGallery, size: togglesSize, dark: true) }

    // QuickCaptureDialog — `.panel` glass, migrated here from
    // `LillistUITests/iOS/iOSSnapshotTests` (it blanked offscreen).
    @MainActor func test_quickCaptureDialog_empty_light()  { snapshot(quickCapture(""), size: captureSize, dark: false) }
    @MainActor func test_quickCaptureDialog_empty_dark()   { snapshot(quickCapture(""), size: captureSize, dark: true) }
    @MainActor func test_quickCaptureDialog_parsed_light() { snapshot(quickCapture("Buy milk #errands ^tomorrow"), size: captureTallSize, dark: false) }
    @MainActor func test_quickCaptureDialog_error_light()  { snapshot(quickCapture("Anything", error: "Couldn't create task"), size: captureTallSize, dark: false) }

    // The interactive status control — its `Menu` hit layer blanks the
    // offscreen capture, so the visual moved here from `iOSSnapshotTests`.
    @MainActor func test_statusIndicator_light() { snapshot(statusGallery, size: statusSize, dark: false) }
    @MainActor func test_statusIndicator_dark()  { snapshot(statusGallery, size: statusSize, dark: true) }

    // The TasksScreen empty state — `RainbowEmptyStateView`, whose
    // `DotGridBackdrop` composites via `.drawingGroup()` (Metal). Like
    // Liquid Glass, Metal does not render in the offscreen
    // `CALayer.render(in:)` capture, so this case moved here from
    // `IOSScreenTourTests` (see docs/engineering-notes.md 2026-06-15).
    @MainActor func test_emptyState_light() { snapshot(emptyState, size: emptySize, dark: false) }
    @MainActor func test_emptyState_dark()  { snapshot(emptyState, size: emptySize, dark: true) }

    // The unified TaskEditorView. Full mode embeds a `StatusIndicatorView`
    // (`Menu` hit layer) so the assembled editor blanks offscreen and must
    // be captured here. Quick mode is the capture card; full mode shows every
    // section over an in-memory draft (collections render empty).
    @MainActor func test_editor_quick_light() async throws { snapshot(try await quickEditor(), size: editorQuickSize, dark: false) }
    @MainActor func test_editor_quick_dark()  async throws { snapshot(try await quickEditor(), size: editorQuickSize, dark: true) }
    @MainActor func test_editor_full_light()  async throws { snapshot(try await fullEditor(), size: editorFullSize, dark: false) }
    @MainActor func test_editor_full_dark()   async throws { snapshot(try await fullEditor(), size: editorFullSize, dark: true) }

    // At the largest accessibility text size the card content overflows the
    // offered height, so the wrap-then-scroll valve must switch to scrolling
    // and keep the header/title visible (never clip). Locks the #22 overflow
    // path the plain-VStack card alone could not guarantee.
    @MainActor func test_editor_full_xxxl_light() async throws {
        snapshot(try await fullEditor().environment(\.dynamicTypeSize, .accessibility5),
                 size: editorFullSize, dark: false)
    }

    /// Non-snapshot regression for #22: the full-mode editor must WRAP to its
    /// content, not fill the offered height. Fails on the pre-fix greedy
    /// `ScrollView` (which reports ~the full offer), passes once the card
    /// self-sizes to ~335pt. The band (#27) has a floor too, so a card that
    /// collapses to nothing also fails, while staying clear of a greedy fill.
    ///
    /// Measures the *content* height (`editorContentHeight`): the single-subtree
    /// `MeasuredGlassCard` (#32) caps its greedy `ScrollView` to the
    /// content's height, measured asynchronously (`onGeometryChange`), so a
    /// one-shot `sizeThatFits` would read the pre-measurement greedy height.
    @MainActor func test_fullEditor_wrapsToContent() async throws {
        let height = editorContentHeight(try await fullEditorModel())
        XCTAssertTrue((250...450).contains(height),
            "Full editor should wrap to its content (~335pt), not fill the offer " +
            "nor collapse — measured \(height)pt")
    }

    /// The fact the tag-field survival test relies on (#27): the fat-notes card's
    /// content is taller than the keyboard-up offer, so raising the keyboard makes
    /// the wrap card cap to the offer and scroll — crossing the fit boundary the
    /// field must survive. Asserts the content height directly:
    /// `MeasuredGlassCard` caps to `min(content, offered)` at runtime, so
    /// `content > offer` ⟹ it scrolls once the keyboard shrinks the offer. Also
    /// checks the seed does real work (taller than the standard card), so the
    /// crossing comes from the long notes, not incidental fixture height.
    @MainActor func test_fatNotesEditor_contentExceedsKeyboardOffer() async throws {
        // Keyboard-up offered height. The screen height is live, but the three
        // subtracted components — status/nav, keyboard, overlay padding — are
        // fixed estimates (PR #25 era) that vary by OS/device, so this isn't the
        // *exact* boundary. Don't assert on the knife-edge: require the fat card
        // to clear the estimate by a healthy margin, so device/keyboard-inset
        // drift (either direction) can't make a green test stop reflecting a real
        // crossing. The survival UITest exercises the actual keyboard-driven
        // crossing on the running device; this is the fast, deterministic proxy
        // that the seed makes a card tall enough to cross with room to spare.
        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.bounds.height ?? 874
        let keyboardUpOffer = screenHeight - 103 - 336 - 48
        let margin: CGFloat = 80

        let fatContent = editorContentHeight(try await fatNotesFullEditorModel())
        let plainContent = editorContentHeight(try await fullEditorModel())

        XCTAssertGreaterThan(fatContent, keyboardUpOffer + margin,
            "Fat-notes card content (\(fatContent)pt) must clear the keyboard-up " +
            "offer (~\(keyboardUpOffer)pt from a \(screenHeight)pt screen) by a " +
            "\(margin)pt margin so it crosses the fit boundary despite inset " +
            "estimates — else the survival test may not overflow when the keyboard rises")
        XCTAssertGreaterThan(fatContent, plainContent,
            "The fat-notes seed must make the card materially taller than the " +
            "standard card (\(fatContent)pt vs \(plainContent)pt) — the boundary " +
            "crossing should come from the long notes, not fixture height")
    }

    /// True content height of the full editor's wrap card — what
    /// `MeasuredGlassCard` measures via `onGeometryChange` and caps its
    /// `ScrollView` to (the card's fitting height at an offer `H` is then just
    /// `min(content, H)`). Probed at a *huge* offer, so the card is never
    /// offer-constrained and reports its full content height.
    ///
    /// The measurement is async: until `onGeometryChange` lands, the card shows a
    /// bounded first-pass height, not its content. Host in a live window and poll
    /// — pump the run loop between `sizeThatFits` reads until the value holds
    /// across several consecutive reads (so a value still transitioning off the
    /// first-pass height can't be mistaken for settled), bounded by a deadline.
    @MainActor
    private func editorContentHeight(_ model: TaskEditorModel) -> CGFloat {
        let host = UIHostingController(rootView: TaskEditorView(model: model, onDismiss: {}))
        let windowSize = CGSize(width: 393, height: 1200)
        host.view.frame = CGRect(origin: .zero, size: windowSize)
        // App-hosted: attach to the host app's live scene so `onGeometryChange`
        // fires. `UIWindow(frame:)` is deprecated on iOS 26 — use the scene.
        guard let scene = foregroundWindowScene() else {
            // Unreachable in the app-hosted bundle (the host app always has a
            // foreground scene); best-effort one-shot fallback if it ever isn't.
            return host.sizeThatFits(in: windowSize).height
        }
        let window = UIWindow(windowScene: scene)
        // Tear the window down so it doesn't outlive the call — a visible window
        // is retained by its scene and would stack across the probe calls.
        defer { window.isHidden = true; window.rootViewController = nil }
        window.frame = host.view.frame
        window.rootViewController = host
        window.isHidden = false

        let probe = CGSize(width: 393, height: 100_000)
        let deadline = Date(timeIntervalSinceNow: 3)
        var last = CGFloat.nan
        var stableReads = 0
        while Date() < deadline {
            host.view.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            host.view.layoutIfNeeded()
            let current = host.sizeThatFits(in: probe).height
            stableReads = (current == last) ? stableReads + 1 : 0
            if stableReads >= 3 { return current }
            last = current
        }
        return last
    }

    // MARK: - fixtures

    private let fabSize = CGSize(width: 220, height: 180)
    private let buttonsSize = CGSize(width: 240, height: 470)
    private let togglesSize = CGSize(width: 280, height: 130)
    private let captureSize = CGSize(width: 380, height: 200)
    private let captureTallSize = CGSize(width: 380, height: 240)
    private let statusSize = CGSize(width: 240, height: 80)
    private let emptySize = CGSize(width: 390, height: 600)
    private let editorQuickSize = CGSize(width: 390, height: 260)
    // The full-mode card now wraps its content (#22), so the fixture frame is
    // sized to hug the wrapped card with a small scrim margin rather than the
    // old near-full-screen 760. The XXXL variant reuses this frame to exercise
    // the wrap-then-scroll overflow path.
    private let editorFullSize = CGSize(width: 393, height: 400)

    /// In-memory store bundle for the editor fixtures (no CloudKit).
    @MainActor
    private func editorStores() async throws -> TaskEditorModel.Stores {
        let p = try await PersistenceController(configuration: .inMemory)
        return TaskEditorModel.Stores(
            tasks: TaskStore(persistence: p),
            tags: TagStore(persistence: p),
            series: SeriesStore(persistence: p),
            journal: JournalStore(persistence: p),
            attachments: AttachmentStore(persistence: p)
        )
    }

    /// Quick-capture draft over the dimmed scrim its real presentation uses.
    @MainActor
    private func quickEditor() async throws -> some View {
        let model = TaskEditorModel(stores: try await editorStores(), opening: .newCapture(parentID: nil, placement: .top))
        model.captureText = "Buy milk #errands ^tomorrow"
        return ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            TaskEditorView(model: model, onDismiss: {})
                .padding(.horizontal, 24)
        }
    }

    /// A full-mode draft with representative scalar fields (no scrim), so
    /// callers can either wrap it in the presentation scrim or measure the
    /// bare card's fitting size.
    @MainActor
    private func fullEditorModel() async throws -> TaskEditorModel {
        let model = TaskEditorModel(stores: try await editorStores(), opening: .newCapture(parentID: nil, placement: .top))
        model.title = "Draft launch email"
        model.notes = "Ship the v1 announcement to the list."
        model.status = .started
        model.deadline = Date(timeIntervalSince1970: 1_780_000_000)
        await model.addTag(name: "launch")
        await model.addTag(name: "marketing")
        model.isPinned = true
        model.mode = .full
        return model
    }

    /// A full-mode draft whose notes body is long enough to drive the
    /// content-hugging notes field (`.lineLimit(2...8)`) to its scroll cap, so
    /// the card is tall enough to cross the keyboard-driven fit boundary. Uses
    /// the shared `UITestSeedContent.fatNotesBody()` so this probe measures the
    /// exact card the `--ui-test-seed-fat-notes` UI test drives.
    @MainActor
    private func fatNotesFullEditorModel() async throws -> TaskEditorModel {
        let model = try await fullEditorModel()
        model.notes = UITestSeedContent.fatNotesBody()
        return model
    }

    /// Full editor over an in-memory draft with representative scalar fields.
    @MainActor
    private func fullEditor() async throws -> some View {
        let model = try await fullEditorModel()
        return ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            TaskEditorView(model: model, onDismiss: {})
                .padding(.horizontal, 16)
        }
    }

    /// Mirrors `TasksScreen`'s no-tasks empty state: the rainbow-gradient
    /// checklist icon, headline + message, dot-grid backdrop, and the
    /// lavender glass "Capture a task" CTA.
    @MainActor
    private var emptyState: some View {
        RainbowEmptyStateView(
            title: "No tasks yet",
            message: "Every open task shows up here. Capture one to get started.",
            systemImage: "checklist"
        ) {
            Button {
            } label: {
                Label("Capture a task", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.rainbow(.lavender))
        }
    }

    /// The iOS Quick Capture dialog (`.panel` Liquid Glass) over the
    /// dimmed scrim its real presentation uses.
    @MainActor
    private func quickCapture(_ text: String, error: String? = nil) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            QuickCaptureDialog(text: .constant(text), errorMessage: error, onSubmit: {})
                .padding(.horizontal, 24)
        }
    }

    /// All four status states of the interactive control (a `Menu` hit
    /// layer over the solid `StatusCubeView` chip), at the 44pt hit size.
    @MainActor
    private var statusGallery: some View {
        ZStack {
            LillistColor.workspace.ignoresSafeArea()
            HStack(spacing: LillistSpacing.l) {
                StatusIndicatorView(status: .todo, onClick: {}, onSetStatus: { _ in })
                StatusIndicatorView(status: .started, onClick: {}, onSetStatus: { _ in })
                StatusIndicatorView(status: .blocked, onClick: {}, onSetStatus: { _ in })
                StatusIndicatorView(status: .closed, onClick: {}, onSetStatus: { _ in })
            }
        }
    }

    /// Every RainbowButtonStyle variant, glass over a rainbow wash.
    @MainActor
    private var buttonGallery: some View {
        let variants: [(String, RainbowButtonStyle.Variant)] = [
            ("Add task", .lavender), ("Delete", .orange), ("Mark done", .green),
            ("Focus", .blue), ("Run intent", .purple), ("Celebrate", .rainbow),
            ("Secondary", .secondary), ("Ghost", .ghost),
        ]
        return ZStack {
            wash
            VStack(spacing: LillistSpacing.m) {
                ForEach(variants, id: \.0) { title, variant in
                    Button(title) {}.buttonStyle(.rainbow(variant))
                }
            }
        }
    }

    /// The Rainbow Glass toggle in both states.
    @MainActor
    private var toggleGallery: some View {
        ZStack {
            wash
            VStack(spacing: LillistSpacing.l) {
                Toggle("Notifications", isOn: .constant(true)).toggleStyle(.rainbow)
                Toggle("Quiet hours", isOn: .constant(false)).toggleStyle(.rainbow)
            }
            .font(LillistTypography.body)
            .foregroundStyle(LillistColor.textBody)
            .padding(.horizontal, LillistSpacing.xl)
        }
    }

    /// A clean rainbow wash (no overlapping text) for the galleries.
    private var wash: some View {
        ZStack {
            LillistColor.workspace
            RainbowGradient.vertical.opacity(0.16)
        }
        .ignoresSafeArea()
    }

    @MainActor
    private var fab: some View { ZStack { backdrop; FloatingAddButton(onTap: {}) } }

    private var backdrop: some View {
        ZStack {
            LillistColor.workspace
            RainbowGradient.vertical.opacity(0.16)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<6, id: \.self) { _ in
                    Text("content refracting through the glass")
                        .font(LillistTypography.subheadline)
                        .foregroundStyle(LillistColor.textBody)
                }
            }
            .padding()
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func snapshot(_ view: some View, size: CGSize, dark: Bool, function: String = #function) {
        let hosted = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = UIHostingController(rootView: hosted)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: size)
        // The editor's `MeasuredGlassCard` sizes to a height `onGeometryChange`
        // reports in a later transaction, so it can't be settled by a run-loop
        // pump on the detached `host.view` (that callback only fires in a live
        // window). It doesn't need to be: `drawHierarchyInKeyWindow` renders
        // `afterScreenUpdates: true`, which flushes pending layout — including the
        // measurement's state update — before the image is captured. So the card
        // is captured at its measured height, not the bounded first-pass one, and
        // (unlike attaching an offscreen live window here) glass still composites
        // correctly. Verified: the `test_editor_full_*` baselines are the
        // populated ~335pt card.
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(
                of: host,
                as: .image(drawHierarchyInKeyWindow: true, size: size),
                testName: function
            )
        }
    }

    /// The host app's foreground window scene, used to host offscreen views in a
    /// live window so `onGeometryChange`-driven layout settles.
    @MainActor
    private func foregroundWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}
