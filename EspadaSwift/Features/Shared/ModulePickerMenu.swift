import SwiftUI

/// Module version picker (Bible, commentary, dictionary, lexicon).
///
/// Smooth sheet open/close: native `.sheet`, solid background, apply selection
/// **after** dismiss so parent reload doesn’t fight the close animation.
struct ModulePickerMenu: View {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let kind: ModuleKind
    let modules: [ModuleInfo]
    let selectedPath: String?
    var availability: [String: Bool] = [:]
    let onSelect: (String?) -> Void

    @State private var showPicker = false
    /// Applied in `onDismiss` so module switch doesn’t jank the sheet close.
    @State private var pendingPath: String??
    @State private var didPick = false

    private var useWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    private var selectedHasContent: Bool {
        guard let path = selectedPath else { return false }
        return availability[path] == true
    }

    private var selectedLabel: String {
        if let path = selectedPath,
           let mod = modules.first(where: { $0.path == path }) {
            return mod.displayName
        }
        return "Elegir \(kind.singularTitle.lowercased())"
    }

    var body: some View {
        Button {
            didPick = false
            pendingPath = nil
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                Text(selectedLabel)
                    .lineLimit(1)
                if selectedHasContent {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Tiene información para este pasaje o palabra")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(themes.theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // Solid pill — glass + popover adaptation made open/close yanky.
            .background(themes.theme.card, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    selectedHasContent
                        ? Color.green.opacity(0.50)
                        : themes.theme.hairline,
                    lineWidth: selectedHasContent ? 1 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(selectedLabel)\(selectedHasContent ? ", con datos" : "")")
        .sheet(isPresented: $showPicker, onDismiss: {
            if didPick, let pending = pendingPath {
                let path = pending
                pendingPath = nil
                didPick = false
                DispatchQueue.main.async {
                    onSelect(path)
                }
            } else {
                pendingPath = nil
                didPick = false
            }
        }) {
            ModuleVersionPickerSheet(
                title: kind == .bible ? "Versión bíblica" : title,
                kind: kind,
                modules: modules,
                selectedPath: selectedPath,
                availability: availability,
                onSelect: { path in
                    pendingPath = .some(path)
                    didPick = true
                    showPicker = false
                },
                onClear: {
                    pendingPath = .some(nil)
                    didPick = true
                    showPicker = false
                },
                onDismiss: {
                    showPicker = false
                }
            )
            .espadaPassagePopoverFrame(wide: useWide)
        }
    }
}

// MARK: - Version list sheet

private struct ModuleVersionPickerSheet: View {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let kind: ModuleKind
    let modules: [ModuleInfo]
    let selectedPath: String?
    var availability: [String: Bool] = [:]
    let onSelect: (String?) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var search = ""
    @State private var allowScrollJump = false

    private var useWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    private var orderedModules: (hits: [ModuleInfo], rest: [ModuleInfo], flat: [ModuleInfo]) {
        ModulePickerOrdering.partition(
            modules: modules,
            availability: availability,
            search: search
        )
    }

    private var sortedModules: [ModuleInfo] { orderedModules.flat }

    private var selectedId: String? {
        guard let selectedPath else { return nil }
        if let mod = modules.first(where: { $0.path == selectedPath }) {
            return mod.id
        }
        let name = (selectedPath as NSString).lastPathComponent.lowercased()
        return modules.first { $0.filename.lowercased() == name }?.id
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if sortedModules.isEmpty {
                    ContentUnavailableView(
                        modules.isEmpty ? "Sin módulos" : "Sin coincidencias",
                        systemImage: "books.vertical",
                        description: Text(
                            modules.isEmpty
                                ? "Importe \(kind.spanishTitle.lowercased()) en Módulos."
                                : "Pruebe otro término de búsqueda."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List {
                            let parts = orderedModules
                            if !parts.hits.isEmpty {
                                Section {
                                    ForEach(parts.hits) { mod in
                                        moduleRow(mod)
                                            .id(mod.id)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                            .listRowBackground(rowBackground(for: mod))
                                    }
                                } header: {
                                    Text("Con contenido")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(themes.theme.secondaryText)
                                        .textCase(nil)
                                }
                                if !parts.rest.isEmpty {
                                    Section {
                                        ForEach(parts.rest) { mod in
                                            moduleRow(mod)
                                                .id(mod.id)
                                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                                .listRowBackground(rowBackground(for: mod))
                                        }
                                    } header: {
                                        Text("Otros")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(themes.theme.secondaryText)
                                            .textCase(nil)
                                    }
                                }
                            } else {
                                ForEach(parts.flat) { mod in
                                    moduleRow(mod)
                                        .id(mod.id)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                        .listRowBackground(rowBackground(for: mod))
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task {
                            // Jump only after present settles — no opacity hide dance.
                            try? await Task.sleep(nanoseconds: 320_000_000)
                            guard !Task.isCancelled else { return }
                            allowScrollJump = true
                            jumpToCurrent(proxy)
                        }
                        .onChange(of: allowScrollJump) { _, ready in
                            if ready { jumpToCurrent(proxy) }
                        }
                        .onChange(of: search) { _, _ in
                            jumpToCurrent(proxy)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themes.theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { onDismiss() }
                        .fontWeight(.medium)
                        .foregroundStyle(themes.theme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedPath != nil {
                        Button("Ninguno") { onClear() }
                            .foregroundStyle(themes.theme.secondaryText)
                    }
                }
            }
            .toolbarBackground(themes.theme.background, for: .navigationBar)
            .toolbarColorScheme(themes.theme.preferredColorScheme, for: .navigationBar)
        }
        // Full-width sheet, solid, smooth system motion.
        .presentationBackground(themes.theme.background)
        .presentationDragIndicator(.visible)
        .presentationDetents(useWide ? [.large] : [.large, .medium])
        .presentationContentInteraction(.scrolls)
    }

    private func jumpToCurrent(_ proxy: ScrollViewProxy) {
        guard allowScrollJump,
              let id = selectedId,
              sortedModules.contains(where: { $0.id == id }) else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(themes.theme.secondaryText)
            TextField("Buscar versión…", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(themes.theme.primaryText)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(themes.theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(themes.theme.card)
        )
    }

    private func moduleRow(_ mod: ModuleInfo) -> some View {
        let isSelected = mod.id == selectedId || mod.path == selectedPath
        let hasData = availability[mod.path] == true

        return Button {
            onSelect(mod.path)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(hasData ? Color.green : themes.theme.secondaryText.opacity(0.25))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mod.displayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(themes.theme.primaryText)
                        .multilineTextAlignment(.leading)
                    if mod.subtitle != mod.displayName {
                        Text(mod.subtitle)
                            .font(.caption)
                            .foregroundStyle(themes.theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(themes.theme.accent)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mod.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func rowBackground(for mod: ModuleInfo) -> some View {
        let isSelected = mod.id == selectedId || mod.path == selectedPath
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? themes.theme.card : themes.theme.background)
            .padding(.vertical, 2)
    }
}

enum ModulePickerOrdering {
    /// - When any module has `availability[path] == true`, those come first (A–Z within group),
    ///   then the rest (A–Z).
    /// - When no hits (nothing selected for dict/lex, or no content for passage), flat A–Z.
    static func partition(
        modules: [ModuleInfo],
        availability: [String: Bool],
        search: String = ""
    ) -> (hits: [ModuleInfo], rest: [ModuleInfo], flat: [ModuleInfo]) {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [ModuleInfo]
        if q.isEmpty {
            filtered = modules
        } else {
            filtered = modules.filter {
                $0.displayName.localizedCaseInsensitiveContains(q)
                    || $0.filename.localizedCaseInsensitiveContains(q)
                    || $0.abbreviation.localizedCaseInsensitiveContains(q)
                    || $0.title.localizedCaseInsensitiveContains(q)
            }
        }

        func alpha(_ a: ModuleInfo, _ b: ModuleInfo) -> Bool {
            a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        let hits = filtered.filter { availability[$0.path] == true }.sorted(by: alpha)
        // Only promote when there is real content for the current study context
        guard !hits.isEmpty else {
            let flat = filtered.sorted(by: alpha)
            return ([], [], flat)
        }
        let hitPaths = Set(hits.map(\.path))
        let rest = filtered.filter { !hitPaths.contains($0.path) }.sorted(by: alpha)
        return (hits, rest, hits + rest)
    }
}

// MARK: - Shared chrome

struct ContextBanner: View {
    @Environment(ThemeManager.self) private var themes
    let text: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(themes.theme.secondaryText)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(themes.theme.primaryText)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(themes.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Limpiar selección")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Soft strip only — no second glass bar + hairline under the nav
        // (those stacked lines made nav + tools look like one thick header).
        .frame(maxWidth: .infinity)
        .background(themes.theme.card.opacity(themes.theme.usesDarkChrome ? 0.55 : 0.92))
    }
}

struct EmptyStateView: View {
    @Environment(ThemeManager.self) private var themes
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .foregroundStyle(themes.theme.primaryText)
        } description: {
            Text(message)
                .foregroundStyle(themes.theme.secondaryText)
        }
    }
}

struct HTMLTextView: View {
    @Environment(StudySession.self) private var session
    let plain: String

    var body: some View {
        LinkableStudyText(plain: plain) { link in
            session.openStudyLink(link)
        }
    }
}
