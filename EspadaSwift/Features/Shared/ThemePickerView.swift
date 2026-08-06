import SwiftUI

/// Appearance picker (font size + themes).
/// - **iPhone:** 2-column theme grid, medium/large sheet.
/// - **iPad:** wider 3-column grid, side-by-side preview, large form / popover.
struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var useWideLayout: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    private var themeColumns: [GridItem] {
        if useWideLayout {
            return [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    var body: some View {
        @Bindable var themes = themes
        NavigationStack {
            ScrollView {
                Group {
                    if useWideLayout {
                        wideContent(themes: themes)
                    } else {
                        phoneContent(themes: themes)
                    }
                }
                .padding(useWideLayout ? 24 : 16)
            }
            .espadaThemedScreen()
            .navigationTitle("Apariencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .espadaFrostedSheet()
        // iPhone: mid-height sheet (higher on screen); iPad: large form / popover
        .espadaThemeSheetChrome(wide: useWideLayout)
    }

    // MARK: - iPad

    @ViewBuilder
    private func wideContent(themes: ThemeManager) -> some View {
        @Bindable var themes = themes
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 20) {
                fontSizeCard(themes: themes)
                    .frame(maxWidth: .infinity)
                previewCard(themes: themes)
                    .frame(maxWidth: .infinity)
            }

            fontFamilyCard(themes: themes)

            VStack(alignment: .leading, spacing: 14) {
                Text("Tema")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themes.theme.primaryText)

                LazyVGrid(columns: themeColumns, spacing: 14) {
                    ForEach(AppTheme.allCases) { theme in
                        themeTile(theme, themes: themes, tall: true)
                    }
                }
            }
        }
    }

    // MARK: - iPhone

    @ViewBuilder
    private func phoneContent(themes: ThemeManager) -> some View {
        @Bindable var themes = themes
        VStack(alignment: .leading, spacing: 24) {
            fontSizeCard(themes: themes)

            fontFamilyCard(themes: themes)

            Text("Tema")
                .font(.headline)
                .foregroundStyle(themes.theme.primaryText)

            LazyVGrid(columns: themeColumns, spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    themeTile(theme, themes: themes, tall: false)
                }
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func fontSizeCard(themes: ThemeManager) -> some View {
        @Bindable var themes = themes
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tamaño del texto", systemImage: "textformat.size")
                    .font(useWideLayout ? .title3.weight(.semibold) : .headline)
                    .foregroundStyle(themes.theme.primaryText)
                Spacer()
                Text("\(Int(themes.bodyFontSize))")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(themes.theme.accent)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
                Text("A")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(themes.theme.secondaryText)
                    .frame(width: 18, alignment: .center)
                Slider(
                    value: $themes.bodyFontSize,
                    in: ThemeManager.minBodyFontSize...ThemeManager.maxBodyFontSize,
                    step: 1
                )
                .tint(themes.theme.accent)
                .accessibilityLabel("Tamaño del texto")
                .accessibilityValue("\(Int(themes.bodyFontSize)) puntos")
                Text("A")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(themes.theme.secondaryText)
                    .frame(width: 28, alignment: .center)
            }

            // Quick sizes for iPad / large print without hunting the slider
            // Fewer chips on phone so the sheet stays short and higher
            let sizes = useWideLayout ? [14, 18, 24, 32, 40, 50] : [14, 18, 24, 32, 50]
            HStack(spacing: 6) {
                ForEach(sizes, id: \.self) { size in
                    let selected = Int(themes.bodyFontSize) == size
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            themes.bodyFontSize = Double(size)
                        }
                    } label: {
                        Text("\(size)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(selected ? Color.white : themes.theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, useWideLayout ? 8 : 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? themes.theme.accent : themes.theme.background.opacity(0.45))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selected ? Color.clear : themes.theme.hairline,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tamaño \(size)")
                }
            }

            if !useWideLayout {
                previewInner(themes: themes)
            }
        }
        .padding(useWideLayout ? 20 : 16)
        .background(cardBackground)
        .overlay(cardStroke)
    }

    @ViewBuilder
    private func fontFamilyCard(themes: ThemeManager) -> some View {
        @Bindable var themes = themes
        VStack(alignment: .leading, spacing: 12) {
            Label("Fuente de lectura", systemImage: "textformat")
                .font(useWideLayout ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(themes.theme.primaryText)

            Text("Español y UI. Hebreo y griego usan Libertinus Serif.")
                .font(.caption)
                .foregroundStyle(themes.theme.secondaryText)

            LazyVGrid(
                columns: useWideLayout
                    ? [GridItem(.adaptive(minimum: 140), spacing: 10)]
                    : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(ReadingFontFamily.allCases) { family in
                    let selected = themes.readingFontFamily == family
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            themes.readingFontFamily = family
                        }
                    } label: {
                        Text(family.label)
                            .font(BibleFont.body(size: 14, family: family))
                            .foregroundStyle(selected ? Color.white : themes.theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? themes.theme.accent : themes.theme.background.opacity(0.45))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        selected ? Color.clear : themes.theme.hairline,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(family.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            // Sample original-language line so users see Libertinus is separate
            Text("αγάπη · אהבה  (Libertinus Serif)")
                .font(BiblicalScriptFont.body(size: max(13, themes.bodyFontSize - 2)))
                .foregroundStyle(themes.theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(useWideLayout ? 20 : 16)
        .background(cardBackground)
        .overlay(cardStroke)
    }

    @ViewBuilder
    private func previewCard(themes: ThemeManager) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vista previa", systemImage: "text.book.closed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(themes.theme.primaryText)
            previewInner(themes: themes)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(cardBackground)
        .overlay(cardStroke)
    }

    private func previewInner(themes: ThemeManager) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !useWideLayout {
                Text("Vista previa")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themes.theme.secondaryText)
            }
            Text("Porque de tal manera amó Dios al mundo, que ha dado a su Hijo unigénito…")
                .font(themes.bodyFont)
                .foregroundStyle(themes.theme.primaryText)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(themes.theme.background.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(themes.theme.hairline, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: themes.bodyFontSize)
                .animation(.easeInOut(duration: 0.2), value: themes.readingFontFamily)
        }
    }

    private func themeTile(_ theme: AppTheme, themes: ThemeManager, tall: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                themes.theme = theme
            }
        } label: {
            VStack(alignment: .leading, spacing: tall ? 12 : 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: theme.swatchColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: tall ? 72 : 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                themes.theme == theme ? theme.accent : themes.theme.hairline,
                                lineWidth: themes.theme == theme ? 2.5 : 1
                            )
                    )

                HStack {
                    Text(theme.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themes.theme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if themes.theme == theme {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(tall ? 14 : 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themes.theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        themes.theme == theme ? themes.theme.accent.opacity(0.45) : themes.theme.hairline,
                        lineWidth: themes.theme == theme ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.label)
        .accessibilityHint(theme.accessibilityHint)
        .accessibilityAddTraits(themes.theme == theme ? .isSelected : [])
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(themes.theme.card)
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(themes.theme.hairline, lineWidth: 1)
    }
}
