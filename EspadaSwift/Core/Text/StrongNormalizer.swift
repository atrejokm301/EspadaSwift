import Foundation

enum StrongNormalizer {
    /// Build lookup variants for a Strong's code (G26, H430, zero-padded, bare digits).
    ///
    /// Important: only **leading** zeros are stripped from the number (`H0430` → core `430`).
    /// Never strip trailing zeros (`H430` must not become `H43`).
    static func candidates(_ raw: String) -> [String] {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return [] }

        var out: [String] = []
        func push(_ x: String) {
            guard !x.isEmpty, !out.contains(x) else { return }
            out.append(x)
        }

        push(s)

        let digitCore: String
        let prefix: Character?

        if let first = s.first, first == "G" || first == "H" {
            prefix = first
            digitCore = stripLeadingZeros(String(s.dropFirst()))
        } else if s.allSatisfy(\.isNumber) {
            prefix = nil
            digitCore = stripLeadingZeros(s)
        } else {
            return out
        }

        guard !digitCore.isEmpty else { return out }

        if let prefix {
            push("\(prefix)\(digitCore)")
            if let n = UInt32(digitCore) {
                push(String(format: "\(prefix)%04d", n))
                push(String(format: "\(prefix)%05d", n))
                push("\(prefix)\(n)")
            }
            push(digitCore)
        } else {
            for p: Character in ["G", "H"] {
                push("\(p)\(digitCore)")
                if let n = UInt32(digitCore) {
                    push(String(format: "\(p)%04d", n))
                    push(String(format: "\(p)%05d", n))
                }
            }
            push(digitCore)
        }

        return out
    }

    /// Strip only leading zeros; keep trailing zeros (H430, G100, H30).
    private static func stripLeadingZeros(_ digits: String) -> String {
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return digits }
        var i = digits.startIndex
        while i < digits.endIndex, digits[i] == "0" {
            i = digits.index(after: i)
        }
        return i == digits.endIndex ? "0" : String(digits[i...])
    }

    static func looksLikeStrong(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard let first = s.first, first == "G" || first == "H" else { return false }
        let rest = s.dropFirst()
        return !rest.isEmpty && rest.allSatisfy(\.isNumber) && rest.count <= 5
    }

    /// Canonical Strong’s form: `G 05463` → `G5463`.
    static func normalize(_ raw: String) -> String {
        if let code = StrongResolve.normalizeStrong(raw) {
            return code
        }
        return candidates(raw).first ?? raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
