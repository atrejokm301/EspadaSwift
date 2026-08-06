import SwiftUI

struct LexiconView: View {
    @Environment(StudySession.self) private var session
    @Environment(ModuleStore.self) private var store
    @Environment(ThemeManager.self) private var themes

    var body: some View {
        @Bindable var session = session
        return NavigationStack {
            VStack(spacing: 0) {
                if session.lexiconNeedsStrongsBible {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                        Text("Siga leyendo Reina Valera 1960. En Módulos, importe una vez «RV1960+ con números Strong» (o iRV 1960+): Espada lo usa en segundo plano para convertir cada palabra al código Strong (H/G) y buscarlo en el léxico — no tiene que leer el módulo con Strong.")
                            .font(.footnote)
                            .foregroundStyle(themes.theme.primaryText)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.14))
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let banner = session.contextBannerText {
                        ContextBanner(text: banner) {
                            session.clearSelection()
                        }
                    }
                    HStack {
                        ModulePickerMenu(
                            title: "Léxico",
                            kind: .lexicon,
                            modules: store.modules(of: .lexicon),
                            selectedPath: session.activeLexiconPath,
                            availability: session.lexiconAvailability
                        ) { path in
                            session.setActiveModule(path: path, kind: .lexicon)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .espadaGlassChromeBar()

                    HStack {
                        Image(systemName: "globe.europe.africa")
                            .foregroundStyle(themes.theme.secondaryText)
                        // Direct bind to session — study taps only write Strong codes here
                        TextField("H3068 / G25…", text: $session.lexiconQueryField)
                            .foregroundStyle(themes.theme.primaryText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { session.searchLexicon(session.lexiconQueryField) }
                        Button("Buscar") {
                            session.searchLexicon(session.lexiconQueryField)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .espadaGlassChromeBar()
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(themes.theme.hairline.opacity(0.85)).frame(height: 0.5)
                    }
                }
            }
            .espadaThemedScreen()
            .navigationTitle("Léxicos")
            .navigationBarTitleDisplayMode(.inline)
            // RV1960 word tap → resolve → strongCode → bar must show H/G, never Spanish
            .onChange(of: session.strongCode) { _, new in
                if let new, StrongNormalizer.looksLikeStrong(new) {
                    session.setLexiconSearchToStrong(new)
                }
            }
            .onChange(of: session.strongHits) { _, hits in
                if let code = hits.first(where: { StrongNormalizer.looksLikeStrong($0.strong) })?.strong {
                    session.setLexiconSearchToStrong(code)
                }
            }
            .onChange(of: session.isResolvingStrongs) { _, resolving in
                if !resolving, let code = session.lexiconStrongForSearchBar {
                    session.setLexiconSearchToStrong(code)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Spinner while mapping to Strong or loading the Strong definition
        if session.isLoadingLexicon || session.isResolvingStrongs {
            VStack(spacing: 12) {
                ProgressView()
                if let code = session.lexiconStrongForSearchBar {
                    Text("Buscando \(code) en el léxico…")
                        .font(.subheadline)
                        .foregroundStyle(themes.theme.secondaryText)
                } else if session.isResolvingStrongs {
                    Text("Mapeando a Strong (H/G)…")
                        .font(.subheadline)
                        .foregroundStyle(themes.theme.secondaryText)
                } else {
                    Text("Buscando…")
                        .font(.subheadline)
                        .foregroundStyle(themes.theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let entry = session.lexiconEntry {
            let ctx = session.lexiconStudyContext
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Spanish word is the headline (not the full verse text)
                    spanishWordCard(ctx: ctx, topic: entry.topic)

                    Divider().overlay(themes.theme.hairline)

                    // Definition from the lexicon module
                    Text("DEFINICIÓN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)

                    LinkableStudyText(plain: entry.plain) { link in
                        session.openStudyLink(link)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(themes.theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(themes.theme.hairline, lineWidth: 1)
                )
                .padding(12)
                .animation(.easeInOut(duration: 0.18), value: themes.bodyFontSize)
            }
            .espadaProMotionScroll()
        } else {
            EmptyStateView(
                systemImage: "globe.europe.africa",
                title: "Léxico",
                message: session.lexiconError
                    ?? "Toque una palabra en RV1960. Espada la convierte al número Strong (H… en AT, G… en NT), lo pone en la búsqueda y abre esa entrada — no busca el español."
            )
        }
    }

    /// Card: bookmark + original (left) + Spanish (right) + Strong — no guillemets «».
    @ViewBuilder
    private func spanishWordCard(ctx: LexiconStudyContext, topic: String) -> some View {
        let spanish = ctx.spanishWord
            ?? session.selectedWord
            ?? session.strongHits.first(where: { StrongResolve.isPlausibleSpanishGloss($0.spanish) })?.spanish
        let strong = ctx.strongCode
            ?? session.strongCode
            ?? (StrongNormalizer.looksLikeStrong(topic) ? StrongNormalizer.normalize(topic) : nil)
        // Original script: interlinear → snippets → any lexicon module’s pre-extracted lemma
        let greek = {
            var candidates = session.strongHits.map(\.greek) + ctx.originalSnippets
            if let s = session.lexiconEntry?.originalScript { candidates.append(s) }
            return candidates.first(where: {
                !$0.isEmpty
                    && !StrongResolve.isMorphologyCode($0)
                    && !StrongResolve.isDottedAnalyticalMorph($0)
            }) ?? ""
        }()
        // Pronunciation for **every** lexicon module (not only Multilexico)
        let translit: String = {
            if let t = session.strongHits.map(\.translit).first(where: {
                StrongResolve.isPlausibleTranslitToken($0)
            }) {
                return t
            }
            if let p = session.lexiconEntry?.pronunciation,
               StrongResolve.isPlausibleTranslitToken(p) {
                return p
            }
            if let plain = session.lexiconEntry?.plain,
               let t = StrongResolve.extractTranslitFromLexiconPlain(plain) {
                return t
            }
            return ""
        }()
        let originalLabel: String = {
            guard !greek.isEmpty else { return "ORIGINAL" }
            let isHeb = greek.unicodeScalars.contains {
                let v = $0.value
                return (v >= 0x0590 && v <= 0x05FF) || (v >= 0xFB1D && v <= 0xFB4F)
            }
            let isGrk = greek.unicodeScalars.contains {
                let v = $0.value
                return (v >= 0x0370 && v <= 0x03FF) || (v >= 0x1F00 && v <= 0x1FFF)
            }
            if isHeb { return "PALABRA EN HEBREO" }
            if isGrk { return "PALABRA EN GRIEGO" }
            return "ORIGINAL"
        }()

        // Size headline fonts from the longer of the two surface forms
        let maxChars = max(spanish?.count ?? 0, greek.count, 4)
        let headlineSize = min(
            max(22, themes.bodyFontSize + 8),
            max(18, CGFloat(34 - max(0, maxChars - 8)))
        )

        VStack(alignment: .leading, spacing: 12) {
            Label(ctx.locationLabel, systemImage: "bookmark.fill")
                .font(themes.captionFont)
                .foregroundStyle(themes.theme.secondaryText)

            // Hebrew/Greek LEFT · Spanish RIGHT (fits any word length without «»)
            HStack(alignment: .top, spacing: 12) {
                // LEFT: original language + pronunciation
                VStack(alignment: .leading, spacing: 4) {
                    Text(originalLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !greek.isEmpty {
                        if let s = strong, !s.isEmpty {
                            Button {
                                session.openStudyLink(.strong(s))
                            } label: {
                                Text(greek)
                                    .font(BiblicalScriptFont.body(size: headlineSize))
                                    .foregroundStyle(themes.theme.accent)
                                    .underline(true, color: themes.theme.accent.opacity(0.4))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(originalLabel): \(greek)")
                        } else {
                            Text(greek)
                                .font(BiblicalScriptFont.body(size: headlineSize))
                                .foregroundStyle(themes.theme.primaryText)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        // How to say it (Latin letters) — not Louw-Nida, not morph
                        if !translit.isEmpty {
                            Text(translit)
                                .font(.system(size: max(15, themes.bodyFontSize - 1), weight: .semibold, design: .serif))
                                .italic()
                                .foregroundStyle(themes.theme.secondaryText)
                                .textSelection(.enabled)
                                .accessibilityLabel("Pronunciación: \(translit)")
                        }
                    } else if !translit.isEmpty {
                        // Pronunciation alone if script missing
                        Text(translit)
                            .font(.system(size: headlineSize, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundStyle(themes.theme.primaryText)
                            .textSelection(.enabled)
                    } else {
                        Text("—")
                            .font(themes.footnoteFont)
                            .foregroundStyle(themes.theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                // RIGHT: Spanish (no « » wrappers)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PALABRA EN ESPAÑOL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let es = spanish, !es.isEmpty {
                        Text(es)
                            .font(.system(size: headlineSize, weight: .bold, design: .serif))
                            .foregroundStyle(themes.theme.primaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text("—")
                            .font(themes.footnoteFont)
                            .foregroundStyle(themes.theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }

            // Strong code
            if let s = strong, !s.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("STRONG")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)
                    Text(s)
                        .font(themes.titleFont.weight(.semibold))
                        .foregroundStyle(themes.theme.accent)
                }
            }

            if !ctx.originalSnippets.isEmpty,
               greek.isEmpty || ctx.originalSnippets.contains(where: { $0 != greek }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HEBREO / GRIEGO EN EL VERSÍCULO")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)
                    FlowChips(
                        items: ctx.originalSnippets,
                        accent: true,
                        onTap: strong.map { code in
                            { _ in session.openStudyLink(.strong(code)) }
                        }
                    )
                }
            }

            if ctx.relatedSpanish.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MISMO STRONG EN EL VERSÍCULO")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(themes.theme.secondaryText)
                    FlowChips(
                        items: ctx.relatedSpanish.filter { StrongResolve.isPlausibleSpanishGloss($0) },
                        accent: false
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themes.theme.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(themes.theme.accent.opacity(0.28), lineWidth: 1)
        )
    }
}

/// Simple wrapping chip row for Spanish glosses / original script.
private struct FlowChips: View {
    @Environment(ThemeManager.self) private var themes
    let items: [String]
    var accent: Bool = false
    /// Optional tap handler (e.g. open Strong peek for Hebrew/Greek chips).
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        WrappingHStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                let chip = Text(item)
                    .font(themes.footnoteFont.weight(.semibold))
                    .foregroundStyle(accent ? themes.theme.accent : themes.theme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(accent ? themes.theme.accent.opacity(0.14) : themes.theme.card)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(themes.theme.hairline, lineWidth: 1)
                    )
                if let onTap {
                    Button {
                        onTap(item)
                    } label: {
                        chip
                    }
                    .buttonStyle(.plain)
                } else {
                    chip
                }
            }
        }
    }
}
