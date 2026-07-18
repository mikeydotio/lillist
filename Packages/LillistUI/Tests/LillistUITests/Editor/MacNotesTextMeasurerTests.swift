#if os(macOS)
import XCTest
@testable import LillistUI

/// Host-runnable coverage for the macOS notes editor's height math (#36).
///
/// Unlike the retired `MacNotesSizerMetricsTests` — which could only pin an
/// *over-count contract* around hand-tuned estimates of undocumented
/// `NSTextView` insets — these exercise the **real** measurement
/// (`MacNotesTextMeasurer`) using the same TextKit config the live view renders
/// with. AppKit text layout composites offscreen without a window, so this runs
/// in plain `swift test` on the Mac host (and in CI).
///
/// Every assertion is a **relation** (never a hardcoded pixel), so the suite
/// stays correct across OS metric bumps — the exact drift #36 worried about.
@MainActor
final class MacNotesTextMeasurerTests: XCTestCase {
    private let wide: CGFloat = 400
    private let narrow: CGFloat = 40

    private func height(_ text: String, _ width: CGFloat) -> CGFloat {
        MacNotesTextMeasurer.height(of: text, width: width)
    }

    /// The config font is body-size and, when the bundled face registered, the
    /// real Jakarta face — a silent system fallback changes every metric.
    func test_configFont_isBodyJakarta() {
        XCTAssertEqual(MacNotesTextConfig.font.pointSize, 15, accuracy: 0.01)
        if LillistFonts.registerIfNeeded() {
            let name = MacNotesTextConfig.font.fontName
            let family = MacNotesTextConfig.font.familyName ?? ""
            XCTAssertTrue(
                name.contains("PlusJakartaSans") || family.contains("Jakarta"),
                "Expected the registered Jakarta face, got \(name)"
            )
        }
    }

    /// The live text view is built from the same config the measurer reads, so
    /// "what is displayed" and "what is measured" cannot diverge. (Replaces the
    /// old over-count contract test.)
    func test_configIdentity_liveViewMatchesMeasurerConfig() {
        let textView = MacNotesTextConfig.makeTextView()
        XCTAssertEqual(textView.font, MacNotesTextConfig.font)
        XCTAssertEqual(textView.textContainerInset, MacNotesTextConfig.textContainerInset)
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, MacNotesTextConfig.lineFragmentPadding)
    }

    /// An empty note measures the same as a one-glyph note — proves the
    /// extra-line-fragment union gives an empty document a real line (no
    /// zero-height box).
    func test_emptyEqualsOneLine() {
        XCTAssertEqual(height("", wide), height("x", wide), accuracy: 1)
    }

    /// A note ending in Return is a line taller than one without — the core
    /// silent-clip case. Two-line variants match whether or not the second line
    /// has glyphs, and a blank line beyond that grows again.
    func test_trailingNewlineAddsALine() {
        let one = height("a", wide)
        let two = height("a\n", wide)
        XCTAssertGreaterThan(two, one)
        XCTAssertEqual(two, height("a\nb", wide), accuracy: 1)
        XCTAssertGreaterThan(height("a\n\n", wide), two)
    }

    /// Hard-newline height grows strictly and near-linearly with line count
    /// (each added line adds ~one line height).
    func test_forcedNewlines_monotonicAndLinear() {
        var previous: CGFloat = 0
        var increments: [CGFloat] = []
        for n in 1...5 {
            let text = Array(repeating: "a", count: n).joined(separator: "\n")
            let h = height(text, wide)
            XCTAssertGreaterThan(h, previous, "height must grow with line \(n)")
            if n > 1 { increments.append(h - previous) }
            previous = h
        }
        let average = increments.reduce(0, +) / CGFloat(increments.count)
        for increment in increments {
            XCTAssertEqual(increment, average, accuracy: 2, "per-line growth should be ~uniform")
        }
    }

    /// A multi-word string in a narrow box wraps to more than one line, and the
    /// wrapped result is taller than a single line — wrapped lines are counted,
    /// the last one isn't dropped (the wrap-boundary clip case).
    func test_wrapAtNarrowWidth_exceedsSingleLine() {
        let wrapped = height("alpha beta gamma delta epsilon zeta", narrow)
        let single = height("alpha", wide)
        XCTAssertGreaterThan(wrapped, single)
    }

    /// Narrower width ⇒ more wraps ⇒ taller; an effectively unbounded width is
    /// the single-line floor for the same text.
    func test_widthMonotonic() {
        let text = "alpha beta gamma delta epsilon zeta eta theta"
        XCTAssertGreaterThan(height(text, narrow), height(text, wide))
        XCTAssertGreaterThanOrEqual(height(text, wide), height(text, .greatestFiniteMagnitude))
    }

    /// The reused scratch layout is not left in a stale state by prior calls:
    /// re-measuring a string returns its original height after interleaved calls.
    func test_determinism_acrossInterleavedCalls() {
        let baseline = height("first line here", wide)
        _ = height("a\nb\nc\nd", narrow)
        _ = height("", wide)
        _ = height("some other text that wraps a lot inside a narrow box", narrow)
        XCTAssertEqual(height("first line here", wide), baseline, accuracy: 0.5)
    }

    /// `clamp` applies the floor and cap independently of raw measurement — why
    /// raw and clamp are separate (tests can observe sub-floor growth).
    func test_clamp_floorsAndCaps() {
        XCTAssertEqual(MacNotesTextMeasurer.clamp(10), MacNotesTextConfig.minHeight)
        XCTAssertEqual(MacNotesTextMeasurer.clamp(100), 100)
        XCTAssertEqual(MacNotesTextMeasurer.clamp(10_000), MacNotesTextConfig.maxHeight)
    }

    /// Very long text measures taller than the cap, so `clamp` pins it to the cap
    /// and the scroll-past-cap path engages (otherwise the scroller never shows).
    func test_rawExceedsCap_forLongText() {
        let raw = height(String(repeating: "line\n", count: 200), wide)
        XCTAssertGreaterThan(raw, MacNotesTextConfig.maxHeight)
        XCTAssertEqual(MacNotesTextMeasurer.clamp(raw), MacNotesTextConfig.maxHeight)
    }

    /// A long unbreakable token yields a finite, positive height (no NaN/∞/hang).
    func test_longUnbreakableToken_finiteHeight() {
        let h = height(String(repeating: "a", count: 500), narrow)
        XCTAssertTrue(h.isFinite)
        XCTAssertGreaterThan(h, 0)
    }
}
#endif
