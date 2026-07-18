import Testing
import Foundation
@testable import LillistUI

/// Regression coverage for #35: the editor `.main` detail card seeded an
/// over-tall height on Back after the inline tag field had been opened.
///
/// The visual symptom is a one-frame blank gap and has no offscreen-capture path
/// (editor/glass snapshots are unavailable off a real host), so these pin the
/// *decision* that prevents it — the same "extract to a testable static, then pin
/// it" move #36 used for the macOS notes sizer — rather than the pixel.
@Suite("Main card height seed (#35)")
struct MainCardHeightSeedTests {

    /// The gate records only while the tag field is collapsed. The card grows only
    /// while `isTagEditing`, so skipping those measurements is what keeps the
    /// remembered height matched to the collapsed card rebuilt on Back.
    @Test("records while collapsed, skips while the tag field is open")
    func gateContract() {
        #expect(TaskEditorView.shouldRememberMainCardHeight(isTagEditing: false))
        #expect(!TaskEditorView.shouldRememberMainCardHeight(isTagEditing: true))
    }

    /// Replays the repro (open editor → +Tag grows the card → drill-in → Back)
    /// through the gate: the grown, tag-open height must never survive as the seed
    /// for the always-collapsed card rebuilt on Back. Before the #35 fix the
    /// recorder was unconditional, so `remembered` would end at `grown` (260).
    @Test("the grown tag-open height never becomes the rebuilt card's seed")
    func grownHeightNeverSeeds() {
        let collapsed: CGFloat = 200
        let grown: CGFloat = 260
        var remembered: CGFloat?

        // Card first measured collapsed → remembered as the seed.
        if TaskEditorView.shouldRememberMainCardHeight(isTagEditing: false) {
            remembered = collapsed
        }
        // Tap +Tag: the field opens, the card grows, geometry fires while editing.
        if TaskEditorView.shouldRememberMainCardHeight(isTagEditing: true) {
            remembered = grown
        }

        #expect(remembered == collapsed)
    }
}

/// The seeding math every `MeasuredGlassCard` shares. The `.attachments`/`.journal`
/// children pass a `maxHeight`, so this clamp is what protects them from an
/// over-tall seed even though they have no tag-field-style transient of their own.
@Suite("Measured card sizing (#35)")
struct MeasuredCardSizingTests {

    /// A bounded child (attachments/journal) can never seed taller than its cap,
    /// so a stale-tall remembered height can't gap the layout; a seed under the cap
    /// passes through unchanged.
    @Test("a bounded child clamps any seed to its cap")
    func boundedChildClampsSeed() {
        #expect(MeasuredCardSizing.cappedHeight(content: 9999, maxHeight: 480) == 480)
        #expect(MeasuredCardSizing.cappedHeight(content: 300, maxHeight: 480) == 300)
    }

    /// The unbounded `.main` card falls back to the first-pass height until it has
    /// measured, then hugs the real content height.
    @Test("an unbounded card falls back to the first-pass height when unmeasured")
    func unboundedFallsBackWhenUnmeasured() {
        #expect(MeasuredCardSizing.cappedHeight(content: 0, maxHeight: nil) == MeasuredCardSizing.firstPassHeight)
        #expect(MeasuredCardSizing.cappedHeight(content: 640, maxHeight: nil) == 640)
    }
}
