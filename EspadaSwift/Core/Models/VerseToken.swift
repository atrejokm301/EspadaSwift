import Foundation

enum TokenKind: String, Hashable, Sendable {
    case word
    case strong
    case punctuation
    case whitespace
    case other
}

struct VerseToken: Identifiable, Hashable, Sendable {
    let id: String
    let kind: TokenKind
    let text: String
    /// Linked Strong's codes for this Spanish word (from interlinear markup).
    let strongCodes: [String]
    let isWordsOfChrist: Bool
    let isInterlinearSpanish: Bool

    init(
        kind: TokenKind,
        text: String,
        strongCodes: [String] = [],
        isWordsOfChrist: Bool = false,
        isInterlinearSpanish: Bool = false,
        idSuffix: String = UUID().uuidString
    ) {
        self.id = "\(kind.rawValue)-\(text)-\(idSuffix)"
        self.kind = kind
        self.text = text
        self.strongCodes = strongCodes
        self.isWordsOfChrist = isWordsOfChrist
        self.isInterlinearSpanish = isInterlinearSpanish
    }

    var primaryStrong: String? { strongCodes.first }

    var isTappableWord: Bool {
        kind == .word && text.rangeOfCharacter(from: .letters) != nil
    }
}
