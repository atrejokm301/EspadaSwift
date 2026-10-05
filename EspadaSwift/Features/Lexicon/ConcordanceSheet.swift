import SwiftUI

/// Every passage using one Strong's code, grouped by book.
///
/// Lives in a sheet rather than in the Léxico card: a common word like H3068 has 5 243
/// hits, and any inline treatment pushes the definition off the screen. The card keeps a
/// one-line summary; the full list is one tap away and gets the whole screen.
struct ConcordanceSheet: View {
    @Environment(StudySession.self) private var session
    @Environment(ThemeManager.self) private var themes
    @Environment(\.dismiss) private var dismiss

    let code: String

    /// Passages bucketed by book, in canonical order.
    private var grouped: [(book: Int, name: String, hits: [StrongIndex.Occurrence])] {
        let buckets = Dictionary(grouping: session.concordanceVerses, by: \.book)
        return buckets.keys.sorted().map { book in
            (
                book: book,
                name: BibleBooks.book(number: book)?.name ?? "Libro \(book)",
                hits: buckets[book]?.sorted {
                    ($0.chapter, $0.verse) < ($1.chapter, $1.verse)
                } ?? []
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.concordanceVerses.isEmpty {
                    EmptyStateView(
                        systemImage: "text.magnifyingglass",
                        title: "Sin concordancia",
                        message: "No hay versículos indexados para \(code)."
                    )
                } else {
                    List {
                        ForEach(grouped, id: \.book) { group in
                            Section {
                                WrappingHStack(alignment: .leading, spacing: 6) {
                                    ForEach(group.hits, id: \.self) { hit in
                                        Button {
                                            session.openConcordanceVerse(hit)
                                            dismiss()
                                        } label: {
                                            Text("\(hit.chapter):\(hit.verse)")
                                                .font(themes.footnoteFont.weight(.semibold))
                                                .foregroundStyle(themes.theme.accent)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 5)
                                                .background(
                                                    Capsule().fill(themes.theme.accent.opacity(0.12))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            } header: {
                                HStack {
                                    Text(group.name)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(themes.theme.primaryText)
                                    Spacer()
                                    Text("\(group.hits.count)")
                                        .font(.caption2)
                                        .foregroundStyle(themes.theme.secondaryText)
                                }
                            }
                            .listRowBackground(themes.theme.card.opacity(0.7))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .espadaProMotionScroll()
                }
            }
            .espadaThemedScreen()
            .navigationTitle(code)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                if session.concordanceTotal > 0 {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(themes.theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .espadaGlassBanner()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(themes.theme.accent)
                }
            }
        }
    }

    private var summary: String {
        let total = session.concordanceTotal
        let shown = session.concordanceVerses.count
        let plural = total == 1 ? "versículo" : "versículos"
        return shown < total
            ? "\(total) \(plural) · mostrando los primeros \(shown)"
            : "\(total) \(plural)"
    }
}
