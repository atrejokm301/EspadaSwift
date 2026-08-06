import SwiftUI

/// Global Bible body renderer: Words of Christ in red from e-Sword markup.
/// Latin uses the selected reading font; Hebrew/Greek always use Libertinus Serif.
struct RedLetterText: View {
    @Environment(ThemeManager.self) private var themes

    /// Raw module Scripture field (HTML / markers).
    let raw: String
    /// Fallback when raw is empty.
    var plainFallback: String = ""
    var fontSize: Double? = nil
    var allowsSelection: Bool = true

    private var size: Double { fontSize ?? themes.bodyFontSize }

    var body: some View {
        Text(attributed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(OptionalTextSelection(enabled: allowsSelection))
            .animation(.easeInOut(duration: 0.18), value: size)
            .animation(.easeInOut(duration: 0.18), value: themes.readingFontFamily)
            .accessibilityLabel(accessibilityPlain)
    }

    private var runs: [BibleTextRun] {
        // Hot path: most Spanish Bibles have no red-letter markup. Never re-run the
        // full HTML pipeline in the view body for every verse (was freezing scrolls /
        // version switches on interlinear chapters).
        if !ESwordText.rawLikelyHasWordsOfChrist(raw) {
            let text = plainFallback.isEmpty
                ? (raw.isEmpty ? "" : ESwordText.moduleFieldToPlain(raw))
                : plainFallback
            return text.isEmpty ? [] : [BibleTextRun(text: text, isWordsOfChrist: false)]
        }
        let fromRaw = ESwordText.readingRuns(from: raw)
        if !fromRaw.isEmpty { return fromRaw }
        if plainFallback.isEmpty { return [] }
        return [BibleTextRun(text: plainFallback, isWordsOfChrist: false)]
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        let base = themes.theme.primaryText
        let woc = themes.theme.wordsOfChrist
        let family = themes.readingFontFamily
        for run in runs {
            let color = run.isWordsOfChrist ? woc : base
            // Per-run Latin vs Hebrew/Greek font assignment
            let piece = ScriptText.attributed(
                run.text,
                size: size,
                latinFamily: family,
                color: color
            )
            result += piece
        }
        return result
    }

    private var accessibilityPlain: String {
        runs.map(\.text).joined()
    }
}

private struct OptionalTextSelection: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}
