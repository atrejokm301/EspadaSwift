import Foundation

enum StrongNormalizer {
    /// Build lookup variants for a Strong's code (G26, H430, zero-padded, bare digits).
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

        let prefix: Character?
        let digits: String

        if s.first == "G" || s.first == "H" {
            prefix = s.first
            digits = String(s.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            if digits.isEmpty, s.dropFirst().allSatisfy({ $0 == "0" }) {
                // keep zero forms below
            }
        } else if s.allSatisfy(\.isNumber) {
            prefix = nil
            digits = s.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        } else {
            return out
        }

        let digitCore: String = {
            if s.first == "G" || s.first == "H" {
                let d = String(s.dropFirst())
                let trimmed = d.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
                return trimmed.isEmpty ? "0" : trimmed
            }
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            return trimmed.isEmpty ? "0" : trimmed
        }()

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

    static func looksLikeStrong(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
