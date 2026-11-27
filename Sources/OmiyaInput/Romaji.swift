struct Romaji {
    private(set) var pending = ""
    private(set) var kana = ""

    var isEmpty: Bool { kana.isEmpty && pending.isEmpty }

    var markedText: String {
        // Letters not yet forming kana stay half-width, as in other IMEs.
        kana + (pending == "nn" ? "ん" : pending)
    }

    var resolvedText: String {
        var copy = self
        copy.finalizePending()
        return copy.kana
    }

    mutating func appendLetter(_ letter: Character) {
        pending.append(letter)
        resolve(final: false)
    }

    mutating func finalizePending() {
        resolve(final: true)
    }

    mutating func appendSymbol(_ symbol: Unicode.Scalar) {
        finalizePending()
        switch symbol {
        case ",": kana.append("、")
        case ".": kana.append("。")
        case "-": kana.append("ー")
        case "[": kana.append("「")
        case "]": kana.append("」")
        case "0"..."9": kana.append(Character(symbol))
        default: kana.append(Self.fullWidth(symbol))
        }
    }

    mutating func deleteLast() {
        if pending == "nn" {
            // "nn" is shown as one ん, so one Delete removes both letters.
            pending = ""
        } else if !pending.isEmpty {
            pending.removeLast()
        } else if !kana.isEmpty {
            kana.removeLast()
        }
        // Letters left over from an earlier unresolved spelling become editable romaji again,
        // so "t" followed by "e" still makes て.
        guard pending.isEmpty else { return }
        while let last = kana.last, last.isASCII, last.isLetter {
            pending.insert(last, at: pending.startIndex)
            kana.removeLast()
        }
    }

    private mutating func resolve(final: Bool) {
        while let first = pending.first {
            if let syllable = Self.syllables[pending] {
                kana += syllable
                pending = ""
                return
            }

            if pending == "nn" {
                if final {
                    kana.append("ん")
                    pending = ""
                }
                return
            }

            if pending.hasPrefix("nn") {
                let next = pending[pending.index(pending.startIndex, offsetBy: 2)]
                // Keep the second n when it starts the next syllable, as in konnichiha.
                kana.append("ん")
                pending.removeFirst("aiueoy".contains(next) ? 1 : 2)
                continue
            }

            if let second = pending.dropFirst().first {
                if first == "n", !"aiueoy".contains(second) {
                    kana.append("ん")
                    pending.removeFirst()
                    continue
                }
                if first == second, Self.geminatingConsonants.contains(first) {
                    kana.append("っ")
                    pending.removeFirst()
                    continue
                }
            }

            if !final, Self.prefixes.contains(pending) {
                return
            }
            kana.append(first == "n" ? "ん" : first)
            pending.removeFirst()
        }
    }

    private static func fullWidth(_ scalar: Unicode.Scalar) -> Character {
        guard let fullWidthScalar = Unicode.Scalar(scalar.value + 0xFEE0) else {
            return Character(scalar)
        }
        return Character(fullWidthScalar)
    }

    private static let geminatingConsonants = Set("bcdfghjkmprstvwxyz")

    private static let syllables: [String: String] = {
        var table: [String: String] = [:]
        let rows: [(String, String)] = [
            ("", "あいうえお"), ("k", "かきくけこ"), ("g", "がぎぐげご"),
            ("s", "さしすせそ"), ("z", "ざじずぜぞ"), ("t", "たちつてと"),
            ("d", "だぢづでど"), ("n", "なにぬねの"), ("h", "はひふへほ"),
            ("b", "ばびぶべぼ"), ("p", "ぱぴぷぺぽ"), ("m", "まみむめも"),
            ("r", "らりるれろ"), ("l", "ぁぃぅぇぉ"), ("x", "ぁぃぅぇぉ")
        ]
        for (prefix, row) in rows {
            for (vowel, kana) in zip("aiueo", row) {
                table[prefix + String(vowel)] = String(kana)
            }
        }

        let contractedRows: [(String, String)] = [
            ("ky", "き"), ("gy", "ぎ"), ("sh", "し"), ("sy", "し"),
            ("j", "じ"), ("jy", "じ"), ("zy", "じ"), ("ch", "ち"),
            ("cy", "ち"), ("ty", "ち"), ("dy", "ぢ"), ("ny", "に"),
            ("hy", "ひ"), ("by", "び"), ("py", "ぴ"), ("my", "み"), ("ry", "り")
        ]
        for (prefix, kana) in contractedRows {
            for (vowel, smallKana) in zip("aueo", "ゃゅぇょ") {
                table[prefix + String(vowel)] = kana + String(smallKana)
            }
        }

        let otherSyllables = [
            "shi": "し", "chi": "ち", "tsu": "つ", "fu": "ふ", "ji": "じ",
            "ya": "や", "yu": "ゆ", "yo": "よ", "wa": "わ", "wo": "を",
            "wi": "うぃ", "we": "うぇ", "ye": "いぇ", "n'": "ん",
            "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ", "fyu": "ふゅ",
            "va": "ゔぁ", "vi": "ゔぃ", "vu": "ゔ", "ve": "ゔぇ", "vo": "ゔぉ",
            "vya": "ゔゃ", "vyu": "ゔゅ", "vyo": "ゔょ",
            "tsa": "つぁ", "tsi": "つぃ", "tse": "つぇ", "tso": "つぉ",
            "thi": "てぃ", "thu": "てゅ", "twu": "とぅ",
            "dhi": "でぃ", "dhu": "でゅ", "dwu": "どぅ",
            "kwa": "くぁ", "gwa": "ぐぁ", "je": "じぇ",
            "tcha": "っちゃ", "tchi": "っち", "tchu": "っちゅ", "tche": "っちぇ", "tcho": "っちょ",
            "xtu": "っ", "xtsu": "っ", "ltu": "っ", "ltsu": "っ",
            "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ", "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ",
            "xwa": "ゎ", "lwa": "ゎ", "xka": "ゕ", "xke": "ゖ"
        ]
        table.merge(otherSyllables) { _, alias in alias }
        return table
    }()

    private static let prefixes = Set(syllables.keys.flatMap { key in
        (1..<key.count).map { String(key.prefix($0)) }
    })
}
