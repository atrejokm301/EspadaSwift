import SwiftUI

/// Book → chapter picker (YouVersion-style).
/// Opens scrolled to the **currently open book** so nearby books are one flick away
/// (e.g. Filipenses → Colosenses), never forced to start at Génesis.
///
/// - **iPhone:** compact abbreviation grid → chapter grid.
/// - **iPad:** side-by-side books + chapters.
struct PassagePickerView: View {
    let selectedBook: Int
    let selectedChapter: Int
    let onSelect: (_ book: Int, _ chapter: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ThemeManager.self) private var themes

    @State private var stage: Stage = .books
    @State private var pendingBook: Int?
    @State private var search = ""
    @State private var testament: Testament = .ot
    /// Bumps after layout so ScrollViewReader can land on the current book.
    @State private var scrollToken = 0

    private enum Stage { case books, chapters }
    private enum Testament: String, CaseIterable { case ot, nt }

    private var useSplitLayout: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    private var ot: [BibleBook] { BibleBooks.all.filter { $0.number <= 39 } }
    private var nt: [BibleBook] { BibleBooks.all.filter { $0.number >= 40 } }

    private var booksForSegment: [BibleBook] {
        filterBooks(testament == .ot ? ot : nt)
    }

    /// Book to keep focused in the list (current reading position).
    private var focusBook: Int {
        pendingBook ?? selectedBook
    }

    private var phoneBookColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 68, maximum: 88), spacing: 8)]
    }

    private var chapterColumns: [GridItem] {
        if useSplitLayout {
            return [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 10)]
        }
        return [GridItem(.adaptive(minimum: 48, maximum: 64), spacing: 8)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themes.theme.background.ignoresSafeArea()
                if useSplitLayout {
                    splitLayout
                } else {
                    phoneLayout
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .espadaThemedScreen()
        }
        .espadaFrostedSheet()
        .espadaSheetChrome(wide: useSplitLayout)
        .onAppear {
            // Match YouVersion: open on the testament + book you're already reading
            testament = selectedBook >= 40 ? .nt : .ot
            pendingBook = selectedBook
            themes.applySystemChrome()
            // Allow list to lay out, then scroll to current book
            scheduleScrollToFocus()
        }
    }

    private var navTitle: String {
        if useSplitLayout { return "Ir a pasaje" }
        if stage == .chapters {
            return BibleBooks.book(number: focusBook)?.abbreviation
                ?? BibleBooks.name(for: focusBook)
        }
        return "Libro"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if useSplitLayout {
                Button("Cerrar") { dismiss() }
                    .fontWeight(.medium)
                    .foregroundStyle(themes.theme.accent)
            } else {
                Button(stage == .chapters ? "Libros" : "Cerrar") {
                    if stage == .chapters {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            stage = .books
                            search = ""
                        }
                        scheduleScrollToFocus()
                    } else {
                        dismiss()
                    }
                }
                .fontWeight(.medium)
                .foregroundStyle(themes.theme.accent)
            }
        }
        if useSplitLayout {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Scroll to current book (YouVersion behavior)

    private func scheduleScrollToFocus() {
        // Multiple passes: first layout is often not ready for ScrollViewReader
        for delay in [0.05, 0.15, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                scrollToken += 1
            }
        }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy, animated: Bool) {
        let target = focusBook
        // If search hides the book, don't jump
        guard booksForSegment.contains(where: { $0.number == target }) else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    // MARK: - iPad

    private var splitLayout: some View {
        HStack(spacing: 0) {
            booksColumnPad
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
                .background(themes.theme.background)

            Rectangle()
                .fill(themes.theme.hairline)
                .frame(width: 1)
                .ignoresSafeArea(edges: .bottom)

            chaptersColumn
                .frame(maxWidth: .infinity)
                .background(themes.theme.background)
        }
    }

    private var booksColumnPad: some View {
        VStack(spacing: 0) {
            testamentPicker
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(booksForSegment) { book in
                            bookRowPad(book)
                                .id(book.number)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
                .onAppear { scrollToFocus(proxy, animated: false) }
                .onChange(of: scrollToken) { _, _ in
                    scrollToFocus(proxy, animated: true)
                }
                .onChange(of: testament) { _, _ in
                    // Keep focus if still in this testament; otherwise first book of segment
                    if !booksForSegment.contains(where: { $0.number == focusBook }) {
                        pendingBook = booksForSegment.first?.number
                    }
                    scheduleScrollToFocus()
                }
                .onChange(of: search) { _, _ in
                    scheduleScrollToFocus()
                }
            }
        }
    }

    private var chaptersColumn: some View {
        let bookNum = focusBook
        let count = BibleBooks.book(number: bookNum)?.chapters ?? 1
        let chapters = Array(1...count)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BibleBooks.name(for: bookNum))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(themes.theme.primaryText)
                        .lineLimit(2)
                    Text("\(count) capítulos")
                        .font(.subheadline)
                        .foregroundStyle(themes.theme.secondaryText)
                }
                Spacer(minLength: 8)
                Text(BibleBooks.book(number: bookNum)?.abbreviation ?? "")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(themes.theme.accent, in: Circle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Rectangle().fill(themes.theme.hairline).frame(height: 1)

            ScrollView {
                LazyVGrid(columns: chapterColumns, spacing: 10) {
                    ForEach(chapters, id: \.self) { ch in
                        chapterCell(book: bookNum, chapter: ch)
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - iPhone

    private var phoneLayout: some View {
        Group {
            switch stage {
            case .books: booksStagePhone
            case .chapters: chaptersStagePhone
            }
        }
    }

    private var booksStagePhone: some View {
        VStack(spacing: 0) {
            testamentPicker
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: phoneBookColumns, spacing: 8) {
                        ForEach(booksForSegment) { book in
                            bookTilePhone(book)
                                .id(book.number)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
                .onAppear { scrollToFocus(proxy, animated: false) }
                .onChange(of: scrollToken) { _, _ in
                    scrollToFocus(proxy, animated: true)
                }
                .onChange(of: testament) { _, _ in
                    if !booksForSegment.contains(where: { $0.number == focusBook }) {
                        pendingBook = booksForSegment.first?.number
                    }
                    scheduleScrollToFocus()
                }
                .onChange(of: search) { _, _ in
                    scheduleScrollToFocus()
                }
            }
        }
    }

    private var chaptersStagePhone: some View {
        let bookNum = focusBook
        let count = BibleBooks.book(number: bookNum)?.chapters ?? 1
        let chapters = Array(1...count)
        let fullName = BibleBooks.name(for: bookNum)
        let abbr = BibleBooks.book(number: bookNum)?.abbreviation ?? ""

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(abbr)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(themes.theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themes.theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("\(count) cap.")
                        .font(.caption)
                        .foregroundStyle(themes.theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(themes.theme.hairline).frame(height: 1)

            ScrollView {
                LazyVGrid(columns: chapterColumns, spacing: 8) {
                    ForEach(chapters, id: \.self) { ch in
                        chapterCell(book: bookNum, chapter: ch)
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - Pieces

    private var testamentPicker: some View {
        Picker("Testamento", selection: $testament) {
            Text("A.T.").tag(Testament.ot)
            Text("N.T.").tag(Testament.nt)
        }
        .pickerStyle(.segmented)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(themes.theme.secondaryText)
            TextField(useSplitLayout ? "Buscar libro…" : "Buscar…", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(themes.theme.primaryText)
                .font(.subheadline)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(themes.theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, useSplitLayout ? 10 : 8)
        .background(themes.theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(themes.theme.hairline, lineWidth: 1))
    }

    private func bookTilePhone(_ book: BibleBook) -> some View {
        let isCurrent = book.number == selectedBook
        let isFocused = book.number == focusBook

        return Button {
            pendingBook = book.number
            search = ""
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                stage = .chapters
            }
        } label: {
            VStack(spacing: 4) {
                Text(shortAbbr(book))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isFocused ? Color.white : themes.theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isCurrent {
                    Text("\(selectedChapter)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isFocused ? Color.white.opacity(0.9) : themes.theme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? themes.theme.accent : themes.theme.card)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isCurrent && !isFocused ? themes.theme.accent.opacity(0.5) : themes.theme.hairline,
                        lineWidth: isCurrent ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(book.name)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private func bookRowPad(_ book: BibleBook) -> some View {
        let isCurrent = book.number == selectedBook
        let isFocused = book.number == focusBook

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                pendingBook = book.number
            }
        } label: {
            HStack(spacing: 12) {
                Text(book.abbreviation)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isFocused ? Color.white : themes.theme.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isFocused ? themes.theme.accent : themes.theme.accent.opacity(0.14))
                    )

                Text(book.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(themes.theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if isCurrent {
                    Text("Cap. \(selectedChapter)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themes.theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(themes.theme.accent.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themes.theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused ? themes.theme.accent.opacity(0.55) : themes.theme.hairline,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(book.name)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private func chapterCell(book: Int, chapter: Int) -> some View {
        let selected = chapter == selectedChapter && book == selectedBook
        return Button {
            onSelect(book, chapter)
            dismiss()
        } label: {
            Text("\(chapter)")
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : themes.theme.primaryText)
                .frame(maxWidth: .infinity, minHeight: useSplitLayout ? 52 : 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? themes.theme.accent : themes.theme.card)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            selected ? Color.clear : themes.theme.hairline,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capítulo \(chapter)")
    }

    private func shortAbbr(_ book: BibleBook) -> String {
        let a = book.abbreviation
        if a.count <= 5 { return a }
        return String(a.prefix(5))
    }

    private func filterBooks(_ books: [BibleBook]) -> [BibleBook] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return books }
        return books.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.abbreviation.localizedCaseInsensitiveContains(q)
        }
    }
}
