import SwiftUI

/// Cross-references for the current verse from TSK-style modules.
/// Opened from the Bible control bar (next to recent verses), not the tab dock.
struct CrossReferenceSheet: View {
    @Environment(StudySession.self) private var session
    @Environment(ModuleStore.self) private var store
    @Environment(ThemeManager.self) private var themes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var useWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    private var modules: [ModuleInfo] {
        session.crossReferenceModules(from: store)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                content
            }
            .espadaThemedScreen()
            .navigationTitle("Referencias cruzadas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(themes.theme.accent)
                }
            }
            .task(id: taskKey) {
                await session.reloadCrossReferences()
            }
        }
        .espadaFrostedSheet()
        .espadaSheetChrome(wide: useWide)
    }

    private var taskKey: String {
        "\(session.activeCrossReferencePath ?? "")-\(session.book)-\(session.chapter)-\(session.verse)"
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.locationLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themes.theme.primaryText)
                Spacer(minLength: 8)
                if !modules.isEmpty {
                    ModulePickerMenu(
                        title: "CR",
                        kind: .commentary,
                        modules: modules,
                        selectedPath: session.activeCrossReferencePath
                    ) { path in
                        session.setActiveCrossReference(path: path)
                    }
                }
            }
            Text("Módulos de referencias cruzadas (TSK, Torrey…)")
                .font(.caption)
                .foregroundStyle(themes.theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .espadaGlassBanner()
        .overlay(alignment: .bottom) {
            Rectangle().fill(themes.theme.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if modules.isEmpty {
            EmptyStateView(
                systemImage: "arrow.left.arrow.right",
                title: "Sin módulos CR",
                message: "Importe un módulo de referencias cruzadas (por ejemplo TSKe / Treasury of Scripture Knowledge) en la pestaña Módulos. Son archivos .cmti con enlaces por versículo."
            )
        } else if session.isLoadingCrossReferences {
            ProgressView("Cargando referencias…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.crossReferenceEntries.isEmpty {
            EmptyStateView(
                systemImage: "link",
                title: "Sin referencias",
                message: session.crossReferenceError
                    ?? "No hay referencias cruzadas para este versículo en el módulo elegido."
            )
        } else {
            List(session.crossReferenceEntries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    if !entry.label.isEmpty {
                        Text(entry.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(themes.theme.secondaryText)
                    }
                    // Tappable <ref> targets jump via StudyPeek → Ir al pasaje
                    HTMLTextView(plain: entry.plain)
                }
                .padding(.vertical, 6)
                .listRowBackground(themes.theme.card.opacity(0.7))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// Small rounded CR button for the Bible control bar.
struct CrossReferenceMenuButton: View {
    @Environment(ThemeManager.self) private var themes

    @Binding var isPresented: Bool
    var onOpen: (() -> Void)? = nil

    var body: some View {
        Button {
            onOpen?()
            isPresented = true
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(themes.theme.primaryText)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                // Solid elevated chip — interactive glass was swallowing taps.
                .espadaGlassChip(shape: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Referencias cruzadas")
        .accessibilityHint("Muestra pasajes relacionados del módulo CR para este versículo")
    }
}
