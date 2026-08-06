import SwiftUI

struct DictionaryView: View {
    @Environment(StudySession.self) private var session
    @Environment(ModuleStore.self) private var store
    @Environment(ThemeManager.self) private var themes
    @State private var query = ""

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if let banner = session.contextBannerText {
                            ContextBanner(text: banner) {
                                session.clearSelection()
                                query = ""
                            }
                        }
                        HStack {
                            ModulePickerMenu(
                                title: "Diccionario",
                                kind: .dictionary,
                                modules: store.modules(of: .dictionary),
                                selectedPath: session.activeDictionaryPath,
                                availability: session.dictionaryAvailability
                            ) { path in
                                session.setActiveModule(path: path, kind: .dictionary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .espadaGlassChromeBar()

                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(themes.theme.secondaryText)
                            TextField("Palabra / tema…", text: $query)
                                .foregroundStyle(themes.theme.primaryText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { session.searchDictionary(query) }
                            if !query.isEmpty {
                                Button {
                                    query = ""
                                    session.clearSelection()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(themes.theme.secondaryText)
                                }
                            }
                            Button("Buscar") {
                                session.searchDictionary(query)
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
                .navigationTitle("Diccionarios")
                .navigationBarTitleDisplayMode(.inline)
            .onChange(of: session.selectedWord) { _, new in
                if let new, !new.isEmpty {
                    query = new
                }
            }
            .onChange(of: session.activeDictionaryPath) { _, _ in
                // Module switch restores last query for that dictionary
                if let w = session.selectedWord, !w.isEmpty {
                    query = w
                }
            }
            .onChange(of: session.focusToken) { _, _ in
                if session.focusedTab == .dictionary, let w = session.selectedWord {
                    query = w
                }
            }
            .task(id: "\(session.selectedWord ?? "")-\(session.activeDictionaryPath ?? "")") {
                if query.isEmpty, let w = session.selectedWord {
                    query = w
                }
                // Badges are refreshed by session navigation (debounced).
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.isLoadingDictionary {
            ProgressView("Buscando…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.dictionaryResults.isEmpty {
            EmptyStateView(
                systemImage: "character.book.closed",
                title: "Diccionario",
                message: session.dictionaryError
                    ?? "Toque una palabra en la Biblia (p. ej. Reina Valera 1960): se busca el español en el diccionario y el Strong en el léxico. Comentarios siguen el versículo/capítulo."
            )
        } else {
            List {
                Section {
                    StudyContextCard(
                        locationLabel: session.locationLabel,
                        spanishWord: session.selectedWord.flatMap {
                            StrongResolve.isPlausibleSpanishGloss($0) ? $0 : nil
                        },
                        strongCode: session.lexiconStrongForSearchBar,
                        subtitle: "Entradas del diccionario para esta palabra"
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(session.dictionaryResults) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.topic)
                            .font(themes.headlineFont)
                            .foregroundStyle(themes.theme.primaryText)
                        // Tappable Strong / refs inside dictionary articles
                        HTMLTextView(plain: entry.plain)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(themes.theme.card)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .espadaProMotionScroll()
            .animation(.easeInOut(duration: 0.18), value: themes.bodyFontSize)
        }
    }
}
