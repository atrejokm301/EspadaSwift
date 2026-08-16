import SwiftUI

/// Small rounded clock button → last 10 verses (popover / sheet).
struct RecentVersesMenu: View {
    @Environment(StudySession.self) private var session
    @Environment(ThemeManager.self) private var themes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var onOpen: (() -> Void)? = nil

    @State private var showList = false

    private var useWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        Button {
            onOpen?()
            showList = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.body.weight(.semibold))
                .foregroundStyle(themes.theme.primaryText)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
                // Frosted glass pill (Kavsoft / Fitness+ floating control style).
                .espadaGlassChip(shape: Circle(), liquid: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Versículos recientes")
        .accessibilityHint("Muestra los últimos 10 versículos visitados")
        // Popover on the Button itself (not nested under GlassEffectContainer).
        .popover(isPresented: $showList, arrowEdge: .top) {
            RecentVersesListSheet(
                onSelect: { entry in
                    session.openRecentVerse(entry)
                    showList = false
                },
                onDismiss: { showList = false }
            )
            .espadaPassagePopoverFrame(wide: useWide)
            .presentationCompactAdaptation(.sheet)
        }
    }
}

private struct RecentVersesListSheet: View {
    @Environment(StudySession.self) private var session
    @Environment(ThemeManager.self) private var themes

    let onSelect: (RecentVerse) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if session.recentVerses.isEmpty {
                    ContentUnavailableView(
                        "Sin recientes",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Al navegar por la Biblia aparecerán aquí sus versículos recientes.")
                    )
                } else {
                    // Card rows (same language as Módulos / version picker) — not a raw List.
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(session.recentVerses) { entry in
                                recentRow(entry)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(themes.theme.background.ignoresSafeArea())
            .navigationTitle("Recientes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { onDismiss() }
                        .fontWeight(.medium)
                        .foregroundStyle(themes.theme.accent)
                }
            }
            .espadaThemedScreen()
        }
        .espadaFrostedSheet()
        .espadaSheetChrome(wide: EspadaAdaptive.isPadDevice)
    }

    private func recentRow(_ entry: RecentVerse) -> some View {
        let isCurrent = entry.book == session.book
            && entry.chapter == session.chapter
            && entry.verse == session.verse
        let abbr = BibleBooks.book(number: entry.book)?.abbreviation
            ?? String(entry.label.prefix(3))

        return Button {
            onSelect(entry)
        } label: {
            HStack(spacing: 12) {
                // Book chip — same visual weight as passage-picker abbr circles
                Text(abbr)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? Color.white : themes.theme.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isCurrent ? themes.theme.accent : themes.theme.accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label)
                        .font(.body.weight(isCurrent ? .semibold : .medium))
                        .foregroundStyle(themes.theme.primaryText)
                        .lineLimit(1)
                    Text("\(BibleBooks.name(for: entry.book)) · cap. \(entry.chapter)")
                        .font(.caption)
                        .foregroundStyle(themes.theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(themes.theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? themes.theme.accent.opacity(0.12) : themes.theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isCurrent ? themes.theme.accent.opacity(0.45) : themes.theme.hairline,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
