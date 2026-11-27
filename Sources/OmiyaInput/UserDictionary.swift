import Foundation

public struct UserDictionaryFile {
    public enum ValidationError: Error {
        case invalidEntry
        case duplicateEntry
    }

    public private(set) var entries: [UserDictionaryEntry]
    private let location: URL

    public init(location: URL) throws {
        self.location = location
        do {
            entries = try JSONDecoder().decode([UserDictionaryEntry].self, from: Data(contentsOf: location))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            entries = []
        }
        try Self.validate(entries)
    }

    public mutating func save(_ entries: [UserDictionaryEntry]) throws {
        try Self.validate(entries)
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: location, options: .atomic)
        self.entries = entries
    }

    private static func validate(_ entries: [UserDictionaryEntry]) throws {
        guard entries.allSatisfy(\.isValid) else { throw ValidationError.invalidEntry }
        guard Set(entries).count == entries.count else { throw ValidationError.duplicateEntry }
    }
}

public struct UserDictionaryConverter: KanaKanjiConverter {
    private let base: any KanaKanjiConverter
    private let entries: () -> [UserDictionaryEntry]

    public init(base: any KanaKanjiConverter, entries: @escaping () -> [UserDictionaryEntry]) {
        self.base = base
        self.entries = entries
    }

    public func convert(_ reading: String, segmentLengths: [Int]?) -> [ConversionSegment]? {
        let matches = entries().filter { reading.contains($0.reading) && $0.isValid }
        let rows = Dictionary(grouping: matches, by: \.reading)
        var result = base.convert(reading, segmentLengths: segmentLengths)

        if !rows.isEmpty, segmentLengths == nil {
            if let original = result,
               let lengths = preferredLengths(reading, result: original, dictionary: rows),
               let resized = base.convert(reading, segmentLengths: lengths),
               resized.map({ $0.reading.unicodeScalars.count }) == lengths,
               resized.map(\.reading).joined() == reading {
                result = resized
            }
            if rows[reading] != nil, result?.count != 1 || result?.first?.reading != reading {
                result = [ConversionSegment(reading: reading, candidates: [])]
            }
        }

        return result?.map { segment in
            let preferred = rows[segment.reading, default: []].map(\.phrase)
            return ConversionSegment(reading: segment.reading, candidates: segment.candidates,
                                     userCandidates: preferred + segment.userCandidates)
        }
    }

    private func preferredLengths(_ reading: String, result: [ConversionSegment],
                                  dictionary: [String: [UserDictionaryEntry]]) -> [Int]? {
        guard result.map(\.reading).joined() == reading else { return nil }
        let originalLengths = result.map { $0.reading.unicodeScalars.count }
        let text = Array(reading.unicodeScalars)
        let keys = Dictionary(grouping: dictionary.keys.map { Array($0.unicodeScalars) },
                              by: { $0.first })
        var edges = Set([0])
        var offset = 0
        for length in originalLengths {
            offset += length
            edges.insert(offset)
        }

        offset = 0
        while offset < text.count {
            let choices = keys[text[offset], default: []]
            guard let matchedLength = choices.lazy.filter({ key in
                key.count <= 255 && text.dropFirst(offset).starts(with: key)
            }).map(\.count).max() else {
                offset += 1
                continue
            }
            let end = offset + matchedLength
            edges = edges.filter { $0 <= offset || $0 >= end }
            edges.insert(offset)
            edges.insert(end)
            offset = end
        }

        let sorted = edges.sorted()
        let sizes = zip(sorted.dropFirst(), sorted).map { end, start in end - start }
        return sizes != originalLengths && sizes.allSatisfy({ (1...255).contains($0) }) ? sizes : nil
    }
}
