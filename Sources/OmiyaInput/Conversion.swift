import Foundation

public protocol KanaKanjiConverter {
    func convert(_ reading: String, segmentLengths: [Int]?) -> [ConversionSegment]?
}

public struct ConversionSegment: Decodable {
    public let reading: String
    public let candidates: [String]
    public let userCandidates: [String]

    public init(reading: String, candidates: [String], userCandidates: [String] = []) {
        self.reading = reading
        self.candidates = candidates
        self.userCandidates = userCandidates
    }

    private enum CodingKeys: String, CodingKey { case reading, candidates }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(reading: try value.decode(String.self, forKey: .reading),
                  candidates: try value.decode([String].self, forKey: .candidates))
    }
}

public struct ConversionPresentation: Equatable, Sendable {
    public let text: String
    public let selection: Range<Int>
    public let visibleCandidates: [String]
    public let selectedCandidate: Int
}

enum CandidatePolicy {
    static func ranked(_ segment: ConversionSegment) -> [String] {
        var seen = Set<String>()
        let user = segment.userCandidates.filter { isAllowedUserPhrase($0) && seen.insert($0).inserted }
        let converted = (segment.candidates + [segment.reading]).filter { isAllowed($0) && seen.insert($0).inserted }
        return user + converted
    }

    /// Words the user registered: English text such as an e-mail address is the user's own choice and
    /// allowed (2026-11-27 user answer); emoji stay excluded (R-08).
    static func isAllowedUserPhrase(_ text: String) -> Bool {
        !text.isEmpty && !text.contains(where: isEmoji)
            && !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    static func isAllowed(_ text: String) -> Bool {
        guard isAllowedUserPhrase(text) else { return false }
        let hasLatin = text.range(of: #"\p{Latin}"#, options: .regularExpression) != nil
        let hasJapanese = text.range(of: #"[\p{Hiragana}\p{Katakana}\p{Han}]"#,
                                     options: .regularExpression) != nil
        return !hasLatin || hasJapanese
    }

    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar == "☺" || scalar == "☻" { return true }
            guard scalar.properties.isEmoji else { continue }

            let next = scalars.dropFirst(index + 1).first
            if next == "\u{FE0F}" || next == "\u{20E3}" { return true }
            if scalar.properties.isEmojiPresentation && next != "\u{FE0E}" { return true }
            if scalars.contains("\u{200D}") { return true }
        }
        return false
    }
}

struct ActiveConversion {
    struct Segment {
        let reading: String
        let candidates: [String]
        var selected = 0

        var text: String { candidates[selected] }
        var length: Int { reading.unicodeScalars.count }
    }

    private(set) var segments: [Segment]
    private(set) var focus = 0
    private(set) var isListVisible = false

    var text: String { segments.map(\.text).joined() }

    var presentation: ConversionPresentation {
        let start = segments[..<focus].reduce(0) { $0 + $1.text.utf16.count }
        let segment = segments[focus]
        return ConversionPresentation(text: text, selection: start..<(start + segment.text.utf16.count),
                                      visibleCandidates: isListVisible ? segment.candidates : [],
                                      selectedCandidate: segment.selected)
    }

    init?(_ result: [ConversionSegment]?, reading: String, lengths: [Int]? = nil) {
        guard let result, !result.isEmpty, result.map(\.reading).joined() == reading else { return nil }
        segments = result.map { Segment(reading: $0.reading, candidates: CandidatePolicy.ranked($0)) }
        guard segments.allSatisfy({ !$0.reading.isEmpty && !$0.candidates.isEmpty }),
              lengths == nil || lengths == segments.map(\.length) else { return nil }
    }

    mutating func showList() {
        isListVisible = true
    }

    mutating func moveCandidate(by amount: Int) {
        let segment = segments[focus]
        let count = segment.candidates.count
        segments[focus].selected = (segment.selected + amount + count) % count
        showList()
    }

    mutating func selectCandidate(_ text: String) -> Bool {
        guard isListVisible, let index = segments[focus].candidates.firstIndex(of: text) else { return false }
        segments[focus].selected = index
        return true
    }

    mutating func moveSegment(by amount: Int) {
        focus = min(max(0, focus + amount), segments.count - 1)
    }

    mutating func resize(by amount: Int, reading: String, converter: any KanaKanjiConverter) {
        var lengths = segments.map(\.length)
        if amount == 1, focus + 1 < lengths.count {
            lengths[focus] += 1
            lengths[focus + 1] -= 1
            if lengths[focus + 1] == 0 { lengths.remove(at: focus + 1) }
        } else if amount == -1, lengths[focus] > 1 {
            lengths[focus] -= 1
            if focus + 1 == lengths.count {
                lengths.append(1)
            } else {
                lengths[focus + 1] += 1
            }
        } else {
            return
        }

        guard let result = Self(converter.convert(reading, segmentLengths: lengths),
                                reading: reading, lengths: lengths) else { return }
        var selections: [Int: Segment] = [:]
        var offset = 0
        for segment in segments {
            selections[offset] = segment
            offset += segment.length
        }

        segments = result.segments
        offset = 0
        for index in segments.indices {
            if let old = selections[offset], old.reading == segments[index].reading,
               let indexToKeep = segments[index].candidates.firstIndex(of: old.text) {
                segments[index].selected = indexToKeep
            }
            offset += segments[index].length
        }
    }
}
