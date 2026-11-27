import Foundation

public struct UserDictionaryEntry: Codable, Hashable, Sendable {
    public let reading: String
    public let phrase: String

    public init(reading: String, phrase: String) {
        self.reading = reading
        self.phrase = phrase
    }

    var isValid: Bool {
        !reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && CandidatePolicy.isAllowed(phrase)
    }
}

public struct AppleDictionaryImport {
    public struct Issue: Equatable {
        public enum Reason: Equatable {
            case invalidFields
            case empty
            case excludedCandidate
            case duplicate
        }

        public let row: Int
        public let reason: Reason
    }

    public enum FormatError: Error {
        case expectedArray
    }

    public let entries: [UserDictionaryEntry]
    public let issues: [Issue]

    public init(data: Data) throws {
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let rows = plist as? [Any] else { throw FormatError.expectedArray }

        var entries: [UserDictionaryEntry] = []
        var issues: [Issue] = []
        var seen = Set<UserDictionaryEntry>()
        for (index, value) in rows.enumerated() {
            let row = index + 1
            guard let fields = value as? [String: Any],
                  let reading = fields["shortcut"] as? String,
                  let phrase = fields["phrase"] as? String else {
                issues.append(Issue(row: row, reason: .invalidFields))
                continue
            }
            guard !reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                issues.append(Issue(row: row, reason: .empty))
                continue
            }
            guard CandidatePolicy.isAllowed(phrase) else {
                issues.append(Issue(row: row, reason: .excludedCandidate))
                continue
            }
            let entry = UserDictionaryEntry(reading: reading, phrase: phrase)
            guard seen.insert(entry).inserted else {
                issues.append(Issue(row: row, reason: .duplicate))
                continue
            }
            entries.append(entry)
        }
        self.entries = entries
        self.issues = issues
    }
}
