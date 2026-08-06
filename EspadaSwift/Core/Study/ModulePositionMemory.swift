import Foundation

/// Per-module memory for study state that is *not* the reading location.
///
/// **Reading location (book/chapter/verse) is global** — one place for the whole app.
/// Switching Bible or commentary versions always stays on that same passage.
/// Never store or restore a separate place per Bible version.
///
/// Dictionary / lexicon still restore their last query when you switch those modules.
struct ModulePositionMemory: Codable, Equatable {
    /// Dictionary / lexicon: last query for that file.
    struct QueryState: Codable, Equatable {
        var query: String
        /// Optional companion (e.g. Spanish word with a Strong code).
        var companion: String?
    }

    /// filename → last dictionary query (restored on module switch)
    var dictionaryQueries: [String: QueryState] = [:]
    /// filename → last lexicon Strong / lemma (restored on module switch)
    var lexiconQueries: [String: QueryState] = [:]
    /// Last testament tab in the book picker ("ot" / "nt")
    var passagePickerTestament: String = "nt"
    /// Last focused book number in the book picker (for scroll restore)
    var passagePickerBook: Int = 43

    static let storageKey = "espada.modulePositionMemory"

    static func load(from defaults: UserDefaults = .standard) -> ModulePositionMemory {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ModulePositionMemory.self, from: data) else {
            return ModulePositionMemory()
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    static func fileKey(path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent.lowercased()
    }
}

/// Spanish + original-language context for the lexicon tab (RV1960 / interlinear).
struct LexiconStudyContext: Equatable, Sendable {
    /// Primary Spanish surface form (e.g. «Jehová», «amó»).
    var spanishWord: String?
    /// Strong code being studied.
    var strongCode: String?
    /// Other Spanish words in the current verse linked to the same Strong.
    var relatedSpanish: [String]
    /// Plain Spanish of the current verse (from active Bible).
    var verseSpanish: String?
    /// Location label, e.g. "Juan 3:16"
    var locationLabel: String
    /// Hebrew / Greek snippets from interlinear tokens when available.
    var originalSnippets: [String]

    var hasSpanish: Bool {
        if let spanishWord, !spanishWord.isEmpty { return true }
        return !relatedSpanish.isEmpty
    }
}
