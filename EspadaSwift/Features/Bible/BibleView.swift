import SwiftUI

struct BibleView: View {
    @Environment(StudySession.self) private var session
    @Environment(ModuleStore.self) private var store
    @Environment(ThemeManager.self) private var themes
    @Environment(ChromeScrollController.self) private var chrome
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showPassagePicker = false
    @State private var showThemePicker = false
    @State private var showCrossReferences = false
    @State private var highlightVerse: Int?
    /// Study mode: tappable words + Strong chips (needed for dict/lex sync).
    /// Off = denser reading; on = word study.
    @State private var studyMode = true
    /// Horizontal chapter morph (swipe left → next, right → previous) — not fling paging.
    @State private var chapterSwipe = ChapterSwipeMorphController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usePadChrome: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    private var chapterIdentity: String {
        "\(session.book)-\(session.chapter)-\(session.activeBiblePath ?? "")"
    }

    var body: some View {
        NavigationStack {
            // Content is full-bleed; chrome overlays it so Gaussian frost can sample
            // the verse text scrolling underneath (same idea as nav + tab dock).
            Group {
                if session.isLoadingChapter {
                    ProgressView("Cargando capítulo…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = session.chapterError, session.chapterVerses.isEmpty {
                    EmptyStateView(
                        systemImage: "book.closed",
                        title: "Biblia",
                        message: err
                    )
                } else {
                    verseList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                topChrome
            }
            .animation(.easeInOut(duration: 0.22), value: chrome.isHidden)
            .animation(.easeInOut(duration: 0.18), value: session.contextBannerText)
            .espadaThemedScreen()
            .navigationTitle("Biblia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        chrome.show()
                        showThemePicker = true
                    } label: {
                        Image(systemName: "paintpalette.fill")
                    }
                    .accessibilityLabel("Temas")
                    // iPad: popover from the palette; iPhone: falls back to sheet
                    .popover(isPresented: $showThemePicker, arrowEdge: .top) {
                        ThemePickerView()
                            .espadaThemePopoverFrame(wide: usePadChrome)
                            .presentationCompactAdaptation(.sheet)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModulePickerMenu(
                        title: "Biblia",
                        kind: .bible,
                        modules: store.modules(of: .bible),
                        selectedPath: session.activeBiblePath
                    ) { path in
                        chrome.show()
                        session.setActiveModule(path: path, kind: .bible)
                    }
                }
            }
            .onChange(of: showPassagePicker) { _, open in
                if open { chrome.show() }
            }
            .onChange(of: showThemePicker) { _, open in
                if open { chrome.show() }
            }
            .onChange(of: showCrossReferences) { _, open in
                if open { chrome.show() }
            }
            .sheet(isPresented: $showCrossReferences) {
                CrossReferenceSheet()
            }
            .sheet(item: Binding(
                get: { highlightVerse.map { IdentifiedVerse(id: $0) } },
                set: { highlightVerse = $0?.id }
            )) { item in
                HighlightSheet(
                    reference: BibleBooks.reference(book: session.book, chapter: session.chapter, verse: item.id),
                    current: session.highlightColor(for: item.id),
                    onPick: { color in
                        session.setHighlight(color, verse: item.id)
                    },
                    onOpenCommentary: {
                        session.selectVerse(item.id)
                        session.focusedTab = .commentary
                        session.focusToken = UUID()
                    }
                )
            }
            .task(id: "\(session.activeBiblePath ?? "")-\(session.book)-\(session.chapter)") {
                await session.reloadChapter()
            }
        }
    }

    /// Overlay chrome under the system nav: one continuous glass strip, one hairline.
    @ViewBuilder
    private var topChrome: some View {
        VStack(spacing: 0) {
            if let banner = session.contextBannerText {
                ContextBanner(text: banner) {
                    session.clearSelection()
                }
            }
            if !chrome.isHidden {
                controlBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Single separator for the whole inset stack (not per-row hairlines).
        .overlay(alignment: .bottom) {
            if session.contextBannerText != nil || !chrome.isHidden {
                Rectangle()
                    .fill(themes.theme.hairline.opacity(0.55))
                    .frame(height: 0.5)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            Button {
                chrome.show()
                showPassagePicker = true
            } label: {
                HStack(spacing: 4) {
                    Text("\(BibleBooks.name(for: session.book)) \(session.chapter)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(themes.theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .espadaGlassChip(shape: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Elegir libro y capítulo")
            // iPad: wide dual-pane popover; iPhone: sheet via compact adaptation
            .popover(isPresented: $showPassagePicker, arrowEdge: .top) {
                PassagePickerView(
                    selectedBook: session.book,
                    selectedChapter: session.chapter
                ) { book, chapter in
                    session.goTo(book: book, chapter: chapter, verse: 1)
                }
                // Never apply iPad minWidth on phone — that was crushing the book picker
                .espadaPassagePopoverFrame(wide: usePadChrome)
                .presentationCompactAdaptation(.sheet)
            }

            // Passage tools next to the location chip (not the bottom tab dock).
            RecentVersesMenu {
                chrome.show()
            }

            CrossReferenceMenuButton(isPresented: $showCrossReferences) {
                chrome.show()
            }

            Spacer(minLength: 4)

            frostIconButton(
                systemName: studyMode ? "text.magnifyingglass" : "text.alignleft",
                label: studyMode ? "Modo estudio activo" : "Modo lectura"
            ) {
                studyMode.toggle()
                if studyMode { session.ensureTokensForSelectedVerse() }
            }

            frostIconButton(systemName: "chevron.left", label: "Capítulo anterior") {
                session.previousChapter()
            }

            frostIconButton(systemName: "chevron.right", label: "Capítulo siguiente") {
                session.nextChapter()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // One continuous Liquid Glass strip under the nav (not free-floating chips).
        .espadaGlassChromeBar()
    }

    private func frostIconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(themes.theme.primaryText)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .espadaGlassChip(shape: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var verseList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(session.chapterVerses) { row in
                        VerseRowView(
                            row: row,
                            isSelected: row.verse == session.verse,
                            highlight: session.highlightColor(for: row.verse),
                            tokens: row.verse == session.verse && studyMode ? session.selectedVerseTokens : nil,
                            studyMode: studyMode && row.verse == session.verse,
                            onSelect: {
                                session.selectVerse(row.verse)
                            },
                            onHighlight: {
                                session.selectVerse(row.verse)
                                highlightVerse = row.verse
                            }
                        )
                        .id(row.verse)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .espadaTrackScrollForChrome(chrome)
            }
            .espadaProMotionScroll()
            .espadaReadingScrollChrome(chrome)
            // Soft morph dissolve between chapters (spring settle — no fling).
            .espadaChapterSwipeMorph(
                controller: chapterSwipe,
                reduceMotion: reduceMotion
            ) { decision in
                commitChapterSwipe(decision)
            }
            .id(chapterIdentity)
            .onChange(of: chapterIdentity) { _, _ in
                // New chapter painted → materialize incoming morph.
                if chapterSwipe.isCommitting || chapterSwipe.opacity < 1 {
                    chapterSwipe.materializeIncoming()
                }
            }
            .onChange(of: session.verse) { _, v in
                scrollToVerse(proxy, verse: v, animated: true)
            }
            // After version switch (or any chapter reload), land on the same verse.
            .onChange(of: session.activeBiblePath) { _, _ in
                scrollToVerse(proxy, verse: session.verse, animated: true, delay: 0.12)
            }
            .onChange(of: session.chapterVerses.count) { _, count in
                guard count > 0 else { return }
                scrollToVerse(proxy, verse: session.verse, animated: false, delay: 0.05)
            }
            .onChange(of: session.isLoadingChapter) { _, loading in
                if !loading, !session.chapterVerses.isEmpty {
                    scrollToVerse(proxy, verse: session.verse, animated: true, delay: 0.08)
                    // Ensure morph completes when SQLite finishes mid-animation.
                    if chapterSwipe.isCommitting {
                        chapterSwipe.materializeIncoming()
                    }
                }
            }
            // Pull down near top while chrome is hidden → reveal tools (vertical only).
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let dx = abs(value.translation.width)
                        let dy = value.translation.height
                        // Don't steal chapter morph; only vertical pull-down.
                        if dy > 40, dy > dx * 1.25 {
                            chrome.show()
                        }
                    }
            )
        }
    }

    private func commitChapterSwipe(_ decision: ChapterSwipeDecision) {
        chrome.show()
        switch decision {
        case .next:
            session.nextChapter()
        case .previous:
            session.previousChapter()
        case .none:
            chapterSwipe.resetVisuals(animated: true)
        }
        // If BCV didn't change (e.g. already at Genesis 1), cancel morph.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if chapterSwipe.isCommitting, session.isLoadingChapter == false {
                // Edge of Bible: still materialize so we don't stay faded out.
                // Identity may be unchanged — force materialize.
                chapterSwipe.materializeIncoming()
            }
        }
    }

    private func scrollToVerse(
        _ proxy: ScrollViewProxy,
        verse: Int,
        animated: Bool,
        delay: TimeInterval = 0
    ) {
        let work = {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(verse, anchor: .center)
                }
            } else {
                proxy.scrollTo(verse, anchor: .center)
            }
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

private struct IdentifiedVerse: Identifiable {
    let id: Int
}

struct VerseRowView: View {
    @Environment(StudySession.self) private var session
    @Environment(ThemeManager.self) private var themes

    let row: VerseRow
    let isSelected: Bool
    let highlight: HighlightColor?
    let tokens: [VerseToken]?
    let studyMode: Bool
    let onSelect: () -> Void
    let onHighlight: () -> Void

    private let corner: CGFloat = 18

    var body: some View {
        // One version only: never stack a second Bible (e.g. RV1960) under the active text.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                onHighlight()
            } label: {
                Text("\(row.verse)")
                    .font(BibleFont.bold(size: max(11, themes.bodyFontSize - 4), family: themes.readingFontFamily))
                    .foregroundStyle(isSelected ? themes.theme.accent : themes.theme.secondaryText)
                    .frame(width: 26, alignment: .trailing)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Versículo \(row.verse). Toque para resaltar.")

            Group {
                if studyMode, let tokens, !tokens.isEmpty {
                    TokenFlowView(tokens: tokens, verse: row.verse)
                } else {
                    // Global red-letter reading path (WOC from module markup)
                    RedLetterText(raw: row.raw, plainFallback: row.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .onLongPressGesture(minimumDuration: 0.35) { onHighlight() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(isSelected ? themes.theme.selectionStroke : Color.clear, lineWidth: 1.25)
        )
    }

    private var backgroundFill: Color {
        if let highlight {
            return highlight.color
        }
        if isSelected {
            return themes.theme.selectionFill
        }
        return Color.clear
    }
}

struct TokenFlowView: View {
    @Environment(StudySession.self) private var session
    @Environment(ThemeManager.self) private var themes
    let tokens: [VerseToken]
    let verse: Int

    var body: some View {
        WrappingHStack(alignment: .leading, spacing: 3) {
            ForEach(tokens) { token in
                tokenView(token)
            }
        }
    }

    private func ink(for token: VerseToken) -> Color {
        token.isWordsOfChrist ? themes.theme.wordsOfChrist : themes.theme.primaryText
    }

    /// Hebrew / Greek → Libertinus Serif only; Latin → selected reading family.
    private func tokenFont(for token: VerseToken, caption: Bool = false) -> Font {
        let size = caption
            ? max(11, themes.bodyFontSize - 4)
            : themes.bodyFontSize
        if ScriptText.isPrimarilyHebrewOrGreek(token.text) {
            return BiblicalScriptFont.body(size: size)
        }
        return caption
            ? BibleFont.caption(size: themes.bodyFontSize, family: themes.readingFontFamily)
            : BibleFont.body(size: size, family: themes.readingFontFamily)
    }

    @ViewBuilder
    private func tokenView(_ token: VerseToken) -> some View {
        switch token.kind {
        case .whitespace:
            Text(" ")
                .font(tokenFont(for: token))
        case .punctuation:
            Text(token.text)
                .font(tokenFont(for: token))
                .foregroundStyle(ink(for: token))
        case .strong:
            Button {
                let nearby = nearbyWord(for: token)
                session.tapStrong(token.text, nearbyWord: nearby, verseNumber: verse)
            } label: {
                Text(token.text)
                    .font(BibleFont.caption(size: themes.bodyFontSize, family: themes.readingFontFamily))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
        case .word, .other:
            if token.isTappableWord {
                Button {
                    session.tapWord(token, verseNumber: verse)
                } label: {
                    Text(token.text)
                        .font(tokenFont(for: token))
                        .foregroundStyle(ink(for: token))
                        .underline(token.strongCodes.isEmpty == false, color: .indigo.opacity(0.45))
                }
                .buttonStyle(.plain)
            } else {
                Text(token.text)
                    .font(tokenFont(for: token))
                    .foregroundStyle(ink(for: token))
            }
        }
    }

    private func nearbyWord(for strong: VerseToken) -> String? {
        // 1) Word token that is *linked* to this Strong code (most accurate)
        let target = Set(StrongNormalizer.candidates(strong.text))
        if !target.isEmpty,
           let linked = tokens.first(where: { tok in
               tok.kind == .word
                   && StrongResolve.isPlausibleSpanishGloss(tok.text)
                   && tok.strongCodes.contains {
                       !Set(StrongNormalizer.candidates($0)).isDisjoint(with: target)
                   }
           }) {
            return linked.text
        }

        guard let idx = tokens.firstIndex(of: strong) else {
            if let w = session.selectedWord, StrongResolve.isPlausibleSpanishGloss(w) {
                return w
            }
            return nil
        }

        // 2) Interlinear order is typically STRONG then Spanish (blu) — look forward first
        for i in (idx + 1)..<tokens.count {
            if tokens[i].kind == .word, StrongResolve.isPlausibleSpanishGloss(tokens[i].text) {
                return tokens[i].text
            }
            // Stop at the next Strong so we don't steal a later word's gloss
            if tokens[i].kind == .strong { break }
        }
        // 3) Fallback: nearest previous Spanish (within one Strong gap)
        for i in stride(from: idx - 1, through: 0, by: -1) {
            if tokens[i].kind == .word, StrongResolve.isPlausibleSpanishGloss(tokens[i].text) {
                return tokens[i].text
            }
            if tokens[i].kind == .strong { break }
        }
        if let w = session.selectedWord, StrongResolve.isPlausibleSpanishGloss(w) {
            return w
        }
        return nil
    }
}

/// Simple wrapping horizontal stack for verse tokens.
struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
