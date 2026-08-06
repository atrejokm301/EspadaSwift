import SwiftUI

struct LibraryView: View {
    @Environment(StudySession.self) private var session
    @Environment(ModuleStore.self) private var store
    @Environment(ThemeManager.self) private var themes

    @State private var isImporterPresented = false
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var showThemePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introCard

                    sectionHeader("Importar")
                    importCard

                    sectionHeader("Apariencia")
                    appearanceCard

                    ForEach(ModuleKind.allCases.filter { $0 != .reference }, id: \.self) { kind in
                        let list = store.modules.filter { $0.kind == kind }
                        sectionHeader("\(kind.spanishTitle) (\(list.count))")
                        if list.isEmpty {
                            emptyCard("Ninguno importado")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(list.enumerated()), id: \.element.id) { index, mod in
                                    moduleRow(mod)
                                    if index < list.count - 1 {
                                        Divider().overlay(themes.theme.hairline).padding(.leading, 16)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(themes.theme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(themes.theme.hairline, lineWidth: 1)
                            )
                        }
                    }

                    let refs = store.modules(of: .reference, includeEncrypted: true)
                    if !refs.isEmpty {
                        sectionHeader("Referencias (\(refs.count))")
                        VStack(spacing: 0) {
                            ForEach(Array(refs.enumerated()), id: \.element.id) { index, mod in
                                moduleRow(mod)
                                if index < refs.count - 1 {
                                    Divider().overlay(themes.theme.hairline).padding(.leading, 16)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(themes.theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(themes.theme.hairline, lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
            .espadaThemedScreen()
            .navigationTitle("Módulos")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if (store.isScanning || isBusy) && store.importProgress == nil {
                    ProgressView("Procesando…")
                        .padding()
                        .background(themes.theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(themes.theme.hairline, lineWidth: 1)
                        )
                }
            }
            .sheet(isPresented: $isImporterPresented) {
                DocumentImportPicker { urls in
                    isImporterPresented = false
                    Task { await importURLs(urls) }
                } onCancel: {
                    isImporterPresented = false
                }
                .ignoresSafeArea()
            }
            // iPad: popover-sized chrome; iPhone: sheet via compact adaptation
            .popover(isPresented: $showThemePicker, arrowEdge: .top) {
                ThemePickerView()
                    .espadaThemePopoverFrame()
                    .presentationCompactAdaptation(.sheet)
            }
            .refreshable {
                await store.rescan()
                session.applyDefaultModules(from: store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await store.rescan()
                            session.applyDefaultModules(from: store)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { themes.applySystemChrome() }
        }
    }

    private var introCard: some View {
        Text("Importe todos los módulos que quiera, desde cualquier carpeta. Luego elija **uno** activo por pestaña. El catálogo no abre todo a la vez.")
            .font(.footnote)
            .foregroundStyle(themes.theme.secondaryText)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themes.theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(themes.theme.hairline, lineWidth: 1)
            )
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Importar archivos o carpetas…", systemImage: "square.and.arrow.down.on.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(themes.theme.accent)
            }
            .disabled(isBusy)

            #if targetEnvironment(simulator)
            Button {
                Task { await importSeedFromMacFolder() }
            } label: {
                Label("Simulador: carpeta de prueba", systemImage: "internaldrive")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(themes.theme.primaryText)
            }
            .disabled(isBusy)
            #endif

            if let progress = store.importProgress {
                ProgressView(value: progress)
                Text(store.importStatus ?? "Importando…")
                    .font(.caption)
                    .foregroundStyle(themes.theme.secondaryText)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(themes.theme.secondaryText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themes.theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(themes.theme.hairline, lineWidth: 1)
        )
    }

    private var appearanceCard: some View {
        Button {
            showThemePicker = true
        } label: {
            HStack {
                Label("Tema y tamaño", systemImage: "paintpalette.fill")
                    .foregroundStyle(themes.theme.primaryText)
                Spacer()
                Text("\(themes.theme.label) · \(Int(themes.bodyFontSize))")
                    .font(.footnote)
                    .foregroundStyle(themes.theme.secondaryText)
                Image(systemName: EspadaAdaptive.isPadDevice ? "chevron.up.chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themes.theme.secondaryText)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themes.theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(themes.theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(themes.theme.secondaryText)
            .padding(.top, 4)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(themes.theme.secondaryText)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themes.theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(themes.theme.hairline, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func moduleRow(_ mod: ModuleInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(mod.displayName)
                        .font(.headline)
                        .foregroundStyle(themes.theme.primaryText)
                    if mod.encrypted { Text("🔒") }
                    if mod.hasStrongs {
                        Text("Strong")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(themes.theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(themes.theme.accent)
                    }
                    Spacer()
                    if isActive(mod) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Text(mod.subtitle)
                    .font(.caption)
                    .foregroundStyle(themes.theme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .contextMenu {
            if !mod.encrypted {
                Button("Usar como \(mod.kind.singularTitle)") {
                    session.setActiveModule(path: mod.path, kind: mod.kind)
                }
            }
            Button("Eliminar", role: .destructive) {
                Task {
                    await store.deleteModule(mod)
                    session.applyDefaultModules(from: store)
                }
            }
        }
    }

    private func isActive(_ mod: ModuleInfo) -> Bool {
        switch mod.kind {
        case .bible: return session.activeBiblePath == mod.path
        case .commentary: return session.activeCommentaryPath == mod.path
        case .dictionary: return session.activeDictionaryPath == mod.path
        case .lexicon: return session.activeLexiconPath == mod.path
        case .reference: return false
        }
    }

    private func importURLs(_ urls: [URL]) async {
        isBusy = true
        defer { isBusy = false }
        // Import runs off the main actor file-by-file; UI only shows progress.
        let result = await store.importFiles(from: urls)
        if result.ok == 0 && result.failed == 0 {
            statusMessage = store.lastError ?? "No se encontraron módulos válidos."
        } else {
            var msg = "Importados: \(result.ok). Omitidos/fallidos: \(result.failed)."
            if result.ok > 20 {
                msg += " Consejo: con muchos módulos grandes, importe en lotes de 10–15."
            }
            if let err = store.lastError, result.failed > 0 {
                msg += " Último error: \(err)"
            }
            statusMessage = msg
        }
        session.applyDefaultModules(from: store)
        await session.reloadChapterSafely()
    }

    #if targetEnvironment(simulator)
    private func importSeedFromMacFolder() async {
        isBusy = true
        defer { isBusy = false }
        let folder = "/Users/amed301/Downloads/for mac espada"
        let preferred = [
            "00Interlineal-iRV 1960+.bbli",
            "01 Diccionario strong.lexi",
            "01 Diccionario Expositivo con numeros Strong Vine.dcti",
            "00A-CEVALLOS NT-INT+.cmti",
            "01-DHH-D.bbli",
        ]
        let urls = preferred
            .map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            let n = await store.importFromFolder(path: folder)
            statusMessage = "Importados \(n) desde carpeta de prueba."
        } else {
            let result = await store.importFiles(from: urls)
            statusMessage = "Semilla: \(result.ok) módulos."
        }
        session.applyDefaultModules(from: store)
        await session.reloadChapter()
    }
    #endif
}
