import Foundation

enum ModuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bible
    case commentary
    case dictionary
    case lexicon
    case reference

    var id: String { rawValue }

    var spanishTitle: String {
        switch self {
        case .bible: return "Biblias"
        case .commentary: return "Comentarios"
        case .dictionary: return "Diccionarios"
        case .lexicon: return "Léxicos"
        case .reference: return "Referencias"
        }
    }

    var singularTitle: String {
        switch self {
        case .bible: return "Biblia"
        case .commentary: return "Comentario"
        case .dictionary: return "Diccionario"
        case .lexicon: return "Léxico"
        case .reference: return "Referencia"
        }
    }

    static func from(fileExtension ext: String) -> ModuleKind? {
        switch ext.lowercased() {
        case "bbli", "bblx", "bbl": return .bible
        case "cmti", "cmtx", "cmt": return .commentary
        case "dcti", "dctx", "dct": return .dictionary
        case "lexi", "lexx", "lex": return .lexicon
        case "refi", "refx", "ref": return .reference
        default: return nil
        }
    }

    static func isLegacyEncryptedExtension(_ ext: String) -> Bool {
        ["bblx", "cmtx", "dctx", "lexx", "refx"].contains(ext.lowercased())
    }
}

struct ModuleInfo: Identifiable, Hashable, Codable, Sendable {
    var id: String { path }
    let path: String
    let filename: String
    let title: String
    let abbreviation: String
    let kind: ModuleKind
    let encrypted: Bool
    let hasStrongs: Bool
    let version: Int

    var displayName: String {
        abbreviation.isEmpty ? title : abbreviation
    }

    var subtitle: String {
        title == abbreviation ? filename : title
    }
}

struct VerseRow: Identifiable, Hashable, Sendable {
    var id: Int { verse }
    let verse: Int
    let raw: String
    let tokens: [VerseToken]
    let plain: String
}

struct StudyEntry: Identifiable, Hashable, Sendable {
    let id: String
    let scope: String
    let label: String
    let plain: String
    let html: String

    init(scope: String, label: String, plain: String, html: String) {
        self.id = "\(scope)-\(label)-\(plain.hashValue)"
        self.scope = scope
        self.label = label
        self.plain = plain
        self.html = html
    }
}

struct DictEntry: Identifiable, Hashable, Sendable {
    var id: String { topic }
    let topic: String
    let plain: String
    let html: String
    /// Hebrew/Greek lemma extracted from the article (any .lexi / .dcti module).
    let originalScript: String
    /// Latin-letter pronunciation / transliteration (any module that provides it).
    let pronunciation: String

    init(
        topic: String,
        plain: String,
        html: String,
        originalScript: String = "",
        pronunciation: String = ""
    ) {
        self.topic = topic
        self.plain = plain
        self.html = html
        self.originalScript = originalScript
        self.pronunciation = pronunciation
    }
}

enum SelectionSource: String, Sendable {
    case wordTap
    case strongTap
    case verseChange
    case search
    case navigation
}

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case bible
    case commentary
    case dictionary
    case lexicon
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bible: return "Biblia"
        case .commentary: return "Coment."
        case .dictionary: return "Diccio."
        case .lexicon: return "Léxico"
        case .library: return "Módulos"
        }
    }

    var systemImage: String {
        switch self {
        case .bible: return "book.fill"
        case .commentary: return "text.bubble.fill"
        case .dictionary: return "character.book.closed.fill"
        case .lexicon: return "globe.europe.africa.fill"
        case .library: return "square.stack.3d.up.fill"
        }
    }
}
