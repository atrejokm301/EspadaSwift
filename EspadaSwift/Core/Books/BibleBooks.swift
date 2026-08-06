import Foundation

struct BibleBook: Identifiable, Hashable, Sendable {
    let number: Int
    let name: String
    let abbreviation: String
    let chapters: Int

    var id: Int { number }
}

enum BibleBooks {
    static let all: [BibleBook] = [
        .init(number: 1, name: "Génesis", abbreviation: "Gn", chapters: 50),
        .init(number: 2, name: "Éxodo", abbreviation: "Éx", chapters: 40),
        .init(number: 3, name: "Levítico", abbreviation: "Lv", chapters: 27),
        .init(number: 4, name: "Números", abbreviation: "Nm", chapters: 36),
        .init(number: 5, name: "Deuteronomio", abbreviation: "Dt", chapters: 34),
        .init(number: 6, name: "Josué", abbreviation: "Jos", chapters: 24),
        .init(number: 7, name: "Jueces", abbreviation: "Jue", chapters: 21),
        .init(number: 8, name: "Rut", abbreviation: "Rt", chapters: 4),
        .init(number: 9, name: "1 Samuel", abbreviation: "1S", chapters: 31),
        .init(number: 10, name: "2 Samuel", abbreviation: "2S", chapters: 24),
        .init(number: 11, name: "1 Reyes", abbreviation: "1R", chapters: 22),
        .init(number: 12, name: "2 Reyes", abbreviation: "2R", chapters: 25),
        .init(number: 13, name: "1 Crónicas", abbreviation: "1Cr", chapters: 29),
        .init(number: 14, name: "2 Crónicas", abbreviation: "2Cr", chapters: 36),
        .init(number: 15, name: "Esdras", abbreviation: "Esd", chapters: 10),
        .init(number: 16, name: "Nehemías", abbreviation: "Neh", chapters: 13),
        .init(number: 17, name: "Ester", abbreviation: "Est", chapters: 10),
        .init(number: 18, name: "Job", abbreviation: "Job", chapters: 42),
        .init(number: 19, name: "Salmos", abbreviation: "Sal", chapters: 150),
        .init(number: 20, name: "Proverbios", abbreviation: "Pr", chapters: 31),
        .init(number: 21, name: "Eclesiastés", abbreviation: "Ec", chapters: 12),
        .init(number: 22, name: "Cantares", abbreviation: "Cnt", chapters: 8),
        .init(number: 23, name: "Isaías", abbreviation: "Is", chapters: 66),
        .init(number: 24, name: "Jeremías", abbreviation: "Jer", chapters: 52),
        .init(number: 25, name: "Lamentaciones", abbreviation: "Lm", chapters: 5),
        .init(number: 26, name: "Ezequiel", abbreviation: "Ez", chapters: 48),
        .init(number: 27, name: "Daniel", abbreviation: "Dn", chapters: 12),
        .init(number: 28, name: "Oseas", abbreviation: "Os", chapters: 14),
        .init(number: 29, name: "Joel", abbreviation: "Jl", chapters: 3),
        .init(number: 30, name: "Amós", abbreviation: "Am", chapters: 9),
        .init(number: 31, name: "Abdías", abbreviation: "Abd", chapters: 1),
        .init(number: 32, name: "Jonás", abbreviation: "Jon", chapters: 4),
        .init(number: 33, name: "Miqueas", abbreviation: "Mi", chapters: 7),
        .init(number: 34, name: "Nahúm", abbreviation: "Nah", chapters: 3),
        .init(number: 35, name: "Habacuc", abbreviation: "Hab", chapters: 3),
        .init(number: 36, name: "Sofonías", abbreviation: "Sof", chapters: 3),
        .init(number: 37, name: "Hageo", abbreviation: "Hag", chapters: 2),
        .init(number: 38, name: "Zacarías", abbreviation: "Zac", chapters: 14),
        .init(number: 39, name: "Malaquías", abbreviation: "Mal", chapters: 4),
        .init(number: 40, name: "Mateo", abbreviation: "Mt", chapters: 28),
        .init(number: 41, name: "Marcos", abbreviation: "Mr", chapters: 16),
        .init(number: 42, name: "Lucas", abbreviation: "Lc", chapters: 24),
        .init(number: 43, name: "Juan", abbreviation: "Jn", chapters: 21),
        .init(number: 44, name: "Hechos", abbreviation: "Hch", chapters: 28),
        .init(number: 45, name: "Romanos", abbreviation: "Ro", chapters: 16),
        .init(number: 46, name: "1 Corintios", abbreviation: "1Co", chapters: 16),
        .init(number: 47, name: "2 Corintios", abbreviation: "2Co", chapters: 13),
        .init(number: 48, name: "Gálatas", abbreviation: "Gá", chapters: 6),
        .init(number: 49, name: "Efesios", abbreviation: "Ef", chapters: 6),
        .init(number: 50, name: "Filipenses", abbreviation: "Fil", chapters: 4),
        .init(number: 51, name: "Colosenses", abbreviation: "Col", chapters: 4),
        .init(number: 52, name: "1 Tesalonicenses", abbreviation: "1Ts", chapters: 5),
        .init(number: 53, name: "2 Tesalonicenses", abbreviation: "2Ts", chapters: 3),
        .init(number: 54, name: "1 Timoteo", abbreviation: "1Ti", chapters: 6),
        .init(number: 55, name: "2 Timoteo", abbreviation: "2Ti", chapters: 4),
        .init(number: 56, name: "Tito", abbreviation: "Tit", chapters: 3),
        .init(number: 57, name: "Filemón", abbreviation: "Flm", chapters: 1),
        .init(number: 58, name: "Hebreos", abbreviation: "He", chapters: 13),
        .init(number: 59, name: "Santiago", abbreviation: "Stg", chapters: 5),
        .init(number: 60, name: "1 Pedro", abbreviation: "1P", chapters: 5),
        .init(number: 61, name: "2 Pedro", abbreviation: "2P", chapters: 3),
        .init(number: 62, name: "1 Juan", abbreviation: "1Jn", chapters: 5),
        .init(number: 63, name: "2 Juan", abbreviation: "2Jn", chapters: 1),
        .init(number: 64, name: "3 Juan", abbreviation: "3Jn", chapters: 1),
        .init(number: 65, name: "Judas", abbreviation: "Jud", chapters: 1),
        .init(number: 66, name: "Apocalipsis", abbreviation: "Ap", chapters: 22),
    ]

    static func book(number: Int) -> BibleBook? {
        all.first { $0.number == number }
    }

    static func name(for number: Int) -> String {
        book(number: number)?.name ?? "Libro \(number)"
    }

    static func reference(book: Int, chapter: Int, verse: Int? = nil) -> String {
        let n = name(for: book)
        if let verse {
            return "\(n) \(chapter):\(verse)"
        }
        return "\(n) \(chapter)"
    }

    // MARK: - Reference parsing (from Espada Mac `books.rs` aliases)

    /// Resolve e-Sword / Spanish / English book names and abbreviations to 1…66.
    static func resolveBook(_ raw: String) -> Int? {
        let key = normalizeBookKey(raw)
        guard !key.isEmpty else { return nil }
        if let n = aliasMap[key] { return n }
        for b in all {
            if normalizeBookKey(b.name) == key { return b.number }
            if normalizeBookKey(b.abbreviation) == key { return b.number }
        }
        return nil
    }

    /// Fold accents / punctuation for alias matching (same idea as Mac `normalize_book_key`).
    static func normalizeBookKey(_ s: String) -> String {
        let folded = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        out.reserveCapacity(folded.count)
        for ch in folded {
            switch ch {
            case "á", "à", "ä", "â": out.append("a")
            case "é", "è", "ë", "ê": out.append("e")
            case "í", "ì", "ï", "î": out.append("i")
            case "ó", "ò", "ö", "ô": out.append("o")
            case "ú", "ù", "ü", "û": out.append("u")
            case "ñ": out.append("n")
            case " ", ".", "_", "-", "’", "'": break
            default:
                if ch.isLetter || ch.isNumber { out.append(ch) }
            }
        }
        return out
    }

    /// Alias → book number (Mac table + common e-Sword module spellings).
    private static let aliasMap: [String: Int] = {
        var map: [String: Int] = [:]
        // Keys are normalized (no accents/punctuation). Include common e-Sword English
        // spellings (Luk, Act, 1Pe, Mat, Joh, Gen.) used in commentaries & lexicons.
        let pairs: [([String], Int)] = [
            (["genesis", "gen", "gn", "ge", "ge"], 1),
            (["exodo", "ex", "exo", "exod", "exodus"], 2),
            (["levitico", "lev", "lv", "le", "leviticus"], 3),
            (["numeros", "num", "nm", "nu", "numbers"], 4),
            (["deuteronomio", "deut", "dt", "deu", "de", "deuteronomy", "duet"], 5),
            (["josue", "jos", "joshua", "josh"], 6),
            (["jueces", "jue", "juec", "jdc", "jdg", "judg", "judges", "jgs"], 7),
            (["rut", "rt", "ru", "ruth"], 8),
            (["1samuel", "1sam", "1s", "1sa", "ism", "isamuel"], 9),
            (["2samuel", "2sam", "2s", "2sa", "iism", "iisamuel"], 10),
            (["1reyes", "1re", "1r", "1ki", "1rey", "1rs", "1kings", "1king"], 11),
            (["2reyes", "2re", "2r", "2ki", "2rey", "2rs", "2kings", "2king"], 12),
            (["1cronicas", "1cr", "1cron", "1ch", "1cro", "1chronicles", "1chr"], 13),
            (["2cronicas", "2cr", "2cron", "2ch", "2cro", "2chronicles", "2chr"], 14),
            (["esdras", "esd", "ezr", "ezra"], 15),
            (["nehemias", "neh", "nehemiah"], 16),
            (["ester", "est", "esther"], 17),
            (["job", "jb"], 18),
            (["salmos", "salmo", "sal", "ps", "psa", "psalm", "sl", "psalms", "pslm"], 19),
            (["proverbios", "prov", "pro", "pr", "prv", "proverbs"], 20),
            (["eclesiastes", "ecl", "ec", "qo", "ecls", "ecclesiastes", "ecc", "eccl"], 21),
            (["cantares", "cant", "cnt", "ct", "song", "can", "cantardelos", "sos", "songs", "songofsongs", "canticles"], 22),
            (["isaias", "isa", "is", "isaiah"], 23),
            (["jeremias", "jer", "jr", "jeremiah"], 24),
            (["lamentaciones", "lam", "lm", "lament", "lamentations"], 25),
            (["ezequiel", "eze", "ez", "ezq", "ezeq", "ezekiel", "ezek"], 26),
            (["daniel", "dan", "dn", "da"], 27),
            (["oseas", "os", "hos", "hosea"], 28),
            (["joel", "jl", "joe"], 29),
            (["amos", "am", "amo"], 30),
            (["abdias", "abd", "ob", "obadiah", "oba"], 31),
            (["jonas", "jon", "jnh", "jonah"], 32),
            (["miqueas", "miq", "mic", "micah"], 33),
            (["nahum", "nah", "na"], 34),
            (["habacuc", "hab", "ha", "habakkuk"], 35),
            (["sofonias", "sof", "zp", "zephaniah", "zep", "zeph"], 36),
            (["hageo", "hag", "hg", "haggai"], 37),
            (["zacarias", "zac", "zc", "zec", "zechariah", "zech"], 38),
            (["malaquias", "mal", "ml", "malachi"], 39),
            (["mateo", "mat", "mt", "matt", "matthew"], 40),
            (["marcos", "mar", "mr", "mc", "mk", "mark"], 41),
            (["lucas", "luc", "lc", "lk", "lu", "luke", "luk"], 42),
            (["juan", "jn", "joh", "jhn", "john"], 43),
            (["hechos", "hech", "hch", "act", "acts", "hecho"], 44),
            (["romanos", "rom", "ro", "rm", "romans", "rom"], 45),
            (["1corintios", "1cor", "1co", "1c", "1corinthians", "icor", "icorinthians"], 46),
            (["2corintios", "2cor", "2co", "2c", "2corinthians", "iicor", "iicorinthians"], 47),
            (["galatas", "gal", "ga", "gl", "galatians", "galat"], 48),
            (["efesios", "ef", "eph", "efes", "efe", "ephesians"], 49),
            (["filipenses", "fil", "php", "flp", "philippians", "phil", "ph"], 50),
            (["colosenses", "col", "co", "colossians", "colos"], 51),
            (["1tesalonicenses", "1tes", "1ts", "1th", "1tesal", "1thess", "1thessalonians", "ithes"], 52),
            (["2tesalonicenses", "2tes", "2ts", "2th", "2tesal", "2thess", "2thessalonians", "iithes"], 53),
            (["1timoteo", "1tim", "1ti", "1tm", "1timothy", "itim"], 54),
            (["2timoteo", "2tim", "2ti", "2tm", "2timothy", "iitim"], 55),
            (["tito", "tit", "tt", "titus"], 56),
            (["filemon", "flm", "phm", "philemon", "phlm"], 57),
            (["hebreos", "heb", "hbr", "hebrews"], 58),
            (["santiago", "sant", "stg", "jas", "jac", "james", "jam"], 59),
            (["1pedro", "1ped", "1p", "1pe", "1pt", "1peter", "1pet", "ipeter", "ipe"], 60),
            (["2pedro", "2ped", "2p", "2pe", "2pt", "2peter", "2pet", "iipeter", "iipe"], 61),
            (["1juan", "1jn", "1jo", "1j", "ijuan", "1john", "1joh", "ijohn"], 62),
            (["2juan", "2jn", "2jo", "2j", "iijuan", "2john", "2joh", "iijohn"], 63),
            (["3juan", "3jn", "3jo", "3j", "iiijuan", "3john", "3joh", "iiijohn"], 64),
            (["judas", "jud", "jude", "jd", "judas"], 65),
            (["apocalipsis", "apoc", "ap", "rev", "revelation", "revel", "apoc"], 66),
        ]
        for (aliases, num) in pairs {
            for a in aliases { map[a] = num }
        }
        // e-Sword Spanish spellings with accents folded via normalize
        for b in all {
            map[normalizeBookKey(b.name)] = b.number
            map[normalizeBookKey(b.abbreviation)] = b.number
        }
        return map
    }()
}
