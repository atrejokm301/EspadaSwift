import SwiftUI

struct CommentaryView: View {
    @Environment(StudySession.self) private var session
    @Environment(ModuleStore.self) private var store
    @Environment(ThemeManager.self) private var themes

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            content
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
                                title: "Comentario",
                                kind: .commentary,
                                modules: store.modules(of: .commentary),
                                selectedPath: session.activeCommentaryPath,
                                availability: session.commentaryAvailability
                            ) { path in
                                session.setActiveModule(path: path, kind: .commentary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .espadaGlassChromeBar()

                        HStack(spacing: 8) {
                            scopeChip("Versículo", isOn: $session.commentaryVerseScope)
                            scopeChip("Capítulo", isOn: $session.commentaryChapterScope)
                            scopeChip("Libro", isOn: $session.commentaryBookScope)
                            Spacer()
                            Text(session.locationLabel)
                                .font(.caption)
                                .foregroundStyle(themes.theme.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .espadaGlassChromeBar()
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(themes.theme.hairline.opacity(0.85)).frame(height: 0.5)
                        }
                    }
                }
                .onChange(of: session.commentaryVerseScope) { _, _ in
                    Task { await session.reloadCommentary() }
                }
                .onChange(of: session.commentaryChapterScope) { _, _ in
                    Task { await session.reloadCommentary() }
                }
                .onChange(of: session.commentaryBookScope) { _, _ in
                    Task { await session.reloadCommentary() }
                }
                .espadaThemedScreen()
                .navigationTitle("Comentarios")
                .navigationBarTitleDisplayMode(.inline)
                .task(id: "\(session.book)-\(session.chapter)-\(session.verse)-\(session.activeCommentaryPath ?? "")") {
                    // Dedupe inside session if navigation already loaded this key.
                    await session.reloadCommentary()
                }
        }
    }

    private var commentaryScopeSummary: String {
        var parts: [String] = []
        if session.commentaryVerseScope { parts.append("versículo") }
        if session.commentaryChapterScope { parts.append("capítulo") }
        if session.commentaryBookScope { parts.append("libro") }
        if parts.isEmpty { return "Active al menos un alcance (Versículo / Capítulo / Libro)" }
        return "Mostrando comentarios de: " + parts.joined(separator: " · ")
    }

    private func scopeChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn.wrappedValue ? themes.theme.accent : themes.theme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (isOn.wrappedValue ? themes.theme.accent.opacity(0.18) : themes.theme.card.opacity(0.7)),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(themes.theme.secondaryText.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if session.isLoadingCommentary {
            ProgressView("Cargando…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.commentaryEntries.isEmpty {
            EmptyStateView(
                systemImage: "text.bubble",
                title: "Comentario",
                message: session.commentaryError
                    ?? "Los comentarios siguen el pasaje: toque un versículo o una palabra en la Biblia. Active Versículo / Capítulo / Libro arriba para no perder notas del módulo."
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
                        subtitle: commentaryScopeSummary
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(session.commentaryEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(themes.theme.secondaryText)
                            Text(entry.scope.uppercased())
                                .font(.caption2)
                                .foregroundStyle(themes.theme.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(themes.theme.card.opacity(0.9), in: Capsule())
                        }
                        // Tappable Strong numbers + Bible refs inside commentary
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
