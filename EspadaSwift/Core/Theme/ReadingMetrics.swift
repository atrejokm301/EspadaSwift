import SwiftUI
import UIKit

/// Spacing that has to grow with the reading font.
///
/// Padding across the app was written as fixed points — 8, 12, 14, 16, 20 — chosen at a
/// default text size. They hold up until the reader enlarges the font, at which point the
/// text grows and the space around it does not: lines crowd the screen edge, the last
/// verse cannot clear the tab dock, and a two-digit verse number stops fitting its gutter.
///
/// These helpers scale from a 17 pt baseline. Below it nothing changes, so existing
/// layouts are untouched at normal sizes; above it, space grows at a gentler rate than the
/// text so large type does not waste the screen.
enum ReadingMetrics {

    /// Size at which the app's hand-tuned constants were chosen.
    static let baselineFontSize: CGFloat = 17

    /// The size the reading font actually renders at.
    ///
    /// `Font.custom(_:size:)` scales with the system text size, so glyphs grow when the
    /// reader enlarges text in iOS Settings even though the app's stored preference never
    /// moves. Scaling spacing off the stored value alone left every metric at baseline for
    /// those readers — the layout stayed cramped no matter how large the text got.
    /// Everything here is therefore driven by the *rendered* size, which matches the app's
    /// own slider when the system size is at its default.
    static func effectiveFontSize(_ stored: CGFloat) -> CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: stored)
    }

    /// How far past the baseline the reader has pushed the font, 0 when at or below it.
    static func growth(_ fontSize: CGFloat) -> CGFloat {
        max(0, fontSize - baselineFontSize)
    }

    /// Outer margin for a column of reading text.
    ///
    /// Margins are near-constant by design. A phone margin exists to keep glyphs off the
    /// bezel, and that need does not grow with the type — scaling it linearly (an earlier
    /// mistake here) spent 30% of the screen on empty space at large sizes. It grows just
    /// enough to stay proportionate, then stops.
    static func horizontalMargin(fontSize rawSize: CGFloat) -> CGFloat {
        let fontSize = effectiveFontSize(rawSize)
        return min(18, 12 + growth(fontSize) * 0.12)
    }

    /// Inset between a verse row's background and its text.
    static func rowInset(fontSize rawSize: CGFloat) -> CGFloat {
        let fontSize = effectiveFontSize(rawSize)
        return min(11, 8 + growth(fontSize) * 0.06)
    }

    /// Size of a verse number, which is **subordinate** to the text it marks.
    ///
    /// Verse numbers are marginalia — reference furniture, not prose. Printed Bibles set
    /// them at roughly half the body size and never let them grow proportionally. Scaling
    /// them 1:1 (`bodyFontSize - 4`) made the gutter balloon to 54 pt at large sizes and
    /// pushed the text into a narrow ribbon. This settles near 50% of body at the top of
    /// the range while leaving the default size exactly as it was.
    /// NOTE: returned in **stored** units, not rendered ones. It is handed to
    /// `Font.custom(_:size:)`, which applies the system multiplier itself — scaling here
    /// too would apply it twice and blow the number up.
    static func verseNumberSize(fontSize: CGFloat) -> CGFloat {
        // Ratio decided against the rendered size, result expressed in stored units.
        let rendered = effectiveFontSize(fontSize)
        let scale = rendered > 0 ? fontSize / rendered : 1
        let renderedNumber = max(11, min(rendered - 4, 13 + growth(rendered) * 0.28))
        return max(11, renderedNumber * scale)
    }

    /// Gutter reserving room for the digits actually drawn, at the subordinate size.
    /// Always reserves at least two digits so the text column does not shift between
    /// verse 9 and verse 10.
    /// Unlike the font size, this is a layout dimension and must match what is drawn,
    /// so it folds in the system multiplier.
    static func verseNumberWidth(verse: Int, fontSize: CGFloat) -> CGFloat {
        let digits = max(2, String(verse).count)
        let rendered = effectiveFontSize(verseNumberSize(fontSize: fontSize))
        return max(26, rendered * 0.62 * CGFloat(digits) + 4)
    }

    /// Space below the last verse so it can scroll clear of the floating tab dock
    /// instead of resting behind it.
    static func bottomClearance(fontSize rawSize: CGFloat) -> CGFloat {
        let fontSize = effectiveFontSize(rawSize)
        return 24 + growth(fontSize) * 1.1
    }

    /// Space above the first verse so it clears the floating chapter pill.
    static func topClearance(fontSize rawSize: CGFloat) -> CGFloat {
        let fontSize = effectiveFontSize(rawSize)
        return 8 + growth(fontSize) * 0.9
    }

    /// Padding inside a study card (lexicon, dictionary, commentary).
    static func cardPadding(fontSize rawSize: CGFloat) -> CGFloat {
        let fontSize = effectiveFontSize(rawSize)
        return 12 + growth(fontSize) * 0.2
    }
}

extension View {
    /// Margins for a scrolling column of Scripture or study prose.
    func espadaReadingMargins(fontSize: CGFloat) -> some View {
        self
            .padding(.horizontal, ReadingMetrics.horizontalMargin(fontSize: fontSize))
            .padding(.top, ReadingMetrics.topClearance(fontSize: fontSize))
            .padding(.bottom, ReadingMetrics.bottomClearance(fontSize: fontSize))
    }
}
