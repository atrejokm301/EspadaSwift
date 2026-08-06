import SwiftUI

/// Popup shown when the user taps a Strong number or Bible reference
/// inside dictionary / lexicon / commentary text.
struct StudyPeekSheet: View {
    @Environment(StudySession.self) private var session
    @Environment(ThemeManager.self) private var themes
    @Environment(\.dismiss) private var dismiss

    let peek: StudyPeek

    @State private var verseRows: [VerseRow] = []
    @State private var strongEntry: DictEntry?
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Cargando…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView("Sin datos", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    content
                }
            }
            .espadaThemedScreen()
            .navigationTitle(peek.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .task(id: peek.id) {
                await load()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch peek {
                case .verse(let book, let chapter, let verse, let verseEnd):
                    Text(label(book: book, chapter: chapter, verse: verse, end: verseEnd))
                        .font(themes.headlineFont)
                        .foregroundStyle(themes.theme.primaryText)
                    if verseRows.isEmpty {
                        Text("No hay texto en la Biblia activa para este pasaje.")
                            .font(themes.bodyFont)
                            .foregroundStyle(themes.theme.secondaryText)
                    } else {
                        ForEach(verseRows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(row.verse)")
                                    .font(themes.footnoteFont.weight(.bold))
                                    .foregroundStyle(themes.theme.secondaryText)
                                    .frame(width: 28, alignment: .trailing)
                                RedLetterText(raw: row.raw, plainFallback: row.plain)
                            }
                        }
                    }
                    if let bible = session.activeBibleTitle {
                        Text("Biblia: \(bible)")
                            .font(themes.footnoteFont)
                            .foregroundStyle(themes.theme.secondaryText)
                    }

                case .strong(let code):
                    Text(code)
                        .font(themes.titleFont)
                        .foregroundStyle(themes.theme.accent)
                    if let entry = strongEntry {
                        Text(entry.topic)
                            .font(themes.headlineFont)
                            .foregroundStyle(themes.theme.primaryText)
                        Divider().overlay(themes.theme.hairline)
                        // Nested links inside the popup definition
                        LinkableStudyText(plain: entry.plain) { nested in
                            session.openStudyLink(nested)
                        }
                    } else {
                        Text("No hay entrada de léxico para \(code) con el módulo actual. Elija un léxico Strong en el menú (punto verde).")
                            .font(themes.bodyFont)
                            .foregroundStyle(themes.theme.secondaryText)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            switch peek {
            case .verse(let book, let chapter, let verse, _):
                Button {
                    session.goTo(book: book, chapter: chapter, verse: verse)
                    session.focusedTab = .bible
                    session.focusToken = UUID()
                    dismiss()
                } label: {
                    Label("Ir al pasaje", systemImage: "book.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            case .strong(let code):
                Button {
                    session.tapStrong(code)
                    dismiss()
                } label: {
                    Label("Abrir en Léxico", systemImage: "globe.europe.africa")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            EspadaGlassBackground(style: .chrome)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func label(book: Int, chapter: Int, verse: Int, end: Int?) -> String {
        if let end, end != verse {
            return "\(BibleBooks.reference(book: book, chapter: chapter, verse: verse))-\(end)"
        }
        return BibleBooks.reference(book: book, chapter: chapter, verse: verse)
    }

    @MainActor
    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        switch peek {
        case .verse(let book, let chapter, let verse, let verseEnd):
            let end = verseEnd ?? verse
            do {
                verseRows = try await session.loadVersePeek(
                    book: book, chapter: chapter, verse: verse, verseEnd: end
                )
            } catch {
                self.error = error.localizedDescription
            }
        case .strong(let code):
            do {
                strongEntry = try await session.loadStrongPeek(code: code)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// What the study popup is showing.
enum StudyPeek: Identifiable, Hashable {
    case verse(book: Int, chapter: Int, verse: Int, verseEnd: Int?)
    case strong(String)

    var id: String {
        switch self {
        case .verse(let b, let c, let v, let e):
            return "v-\(b)-\(c)-\(v)-\(e ?? v)"
        case .strong(let code):
            return "s-\(code)"
        }
    }

    var title: String {
        switch self {
        case .verse: return "Pasaje"
        case .strong: return "Strong"
        }
    }

    init(link: StudyLink) {
        switch link {
        case .strong(let code):
            self = .strong(code)
        case .verse(let book, let chapter, let verse, let verseEnd):
            self = .verse(book: book, chapter: chapter, verse: verse, verseEnd: verseEnd)
        }
    }
}

/// Study text with tappable Strong numbers and Bible references.
/// Latin uses the selected reading font; Hebrew/Greek → Libertinus Serif only.
struct LinkableStudyText: View {
    @Environment(ThemeManager.self) private var themes
    let plain: String
    var onLink: (StudyLink) -> Void

    var body: some View {
        Text(displayAttributed)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                if let link = StudyLink.from(url: url) {
                    onLink(link)
                    return .handled
                }
                return .systemAction
            })
            .animation(.easeInOut(duration: 0.18), value: themes.bodyFontSize)
            .animation(.easeInOut(duration: 0.18), value: themes.readingFontFamily)
    }

    private var displayAttributed: AttributedString {
        let linked = StudyLinkParser.attributed(
            plain,
            bodyColor: themes.theme.primaryText,
            linkColor: themes.theme.accent
        )
        return ScriptText.applyScriptFonts(
            to: linked,
            source: plain,
            size: themes.bodyFontSize,
            latinFamily: themes.readingFontFamily
        )
    }
}
