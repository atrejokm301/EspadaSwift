import SwiftUI

/// Shared study context strip: bookmark location + optional Spanish word.
/// Used by Diccionario / Comentario / (and mirrors Lexicon bookmark row).
struct StudyContextCard: View {
    @Environment(ThemeManager.self) private var themes

    let locationLabel: String
    var spanishWord: String? = nil
    var strongCode: String? = nil
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(locationLabel, systemImage: "bookmark.fill")
                .font(themes.captionFont)
                .foregroundStyle(themes.theme.secondaryText)

            if let es = spanishWord, !es.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PALABRA EN ESPAÑOL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)
                    // No « » wrappers — plain Spanish surface form only
                    Text(es)
                        .font(.system(size: max(20, themes.bodyFontSize + 4), weight: .bold, design: .serif))
                        .foregroundStyle(themes.theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            if let s = strongCode, !s.isEmpty, StrongNormalizer.looksLikeStrong(s) {
                HStack(spacing: 6) {
                    Text("STRONG")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)
                    Text(StrongNormalizer.normalize(s))
                        .font(themes.footnoteFont.weight(.semibold))
                        .foregroundStyle(themes.theme.accent)
                }
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(themes.footnoteFont)
                    .foregroundStyle(themes.theme.secondaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themes.theme.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(themes.theme.accent.opacity(0.22), lineWidth: 1)
        )
    }
}
