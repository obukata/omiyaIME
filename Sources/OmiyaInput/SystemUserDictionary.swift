import Foundation
import SQLite3

/// Reads the macOS user dictionary (shared with Text Replacements) in place, read-only, so words
/// registered in the standard IME are used without importing them.
///
/// The store is Apple's private Core Data file, not a documented format (checked 2026-11-27 on
/// macOS 26.5.2). Any read failure yields no entries, leaving the plist import as the fallback.
public final class SystemUserDictionary: @unchecked Sendable {
    public static let defaultLocation = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/KeyboardServices/TextReplacements.db", directoryHint: .notDirectory)

    private let location: URL
    private let lock = NSLock()
    private var stamp: [Date?]?
    private var cached: [UserDictionaryEntry] = []

    public init(location: URL = SystemUserDictionary.defaultLocation) {
        self.location = location
    }

    /// Current entries. The file is read again only after it (or its write-ahead log) changes.
    public var entries: [UserDictionaryEntry] {
        lock.withLock {
            let current = [location, URL(fileURLWithPath: location.path + "-wal")].map(Self.modificationDate)
            if current != stamp {
                cached = Self.read(location)
                stamp = current
            }
            return cached
        }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private static func read(_ url: URL) -> [UserDictionaryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.absoluteString + "?mode=ro", &database,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(database, 200)

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = """
            SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY
            WHERE ZWASDELETED IS NULL OR ZWASDELETED = 0
            ORDER BY Z_PK
            """
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }

        var seen = Set<UserDictionaryEntry>()
        var entries: [UserDictionaryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let reading = sqlite3_column_text(statement, 0),
                  let phrase = sqlite3_column_text(statement, 1) else { continue }
            let entry = UserDictionaryEntry(reading: String(cString: reading), phrase: String(cString: phrase))
            // English shortcuts (e.g. "omw") have readings romaji input never produces, so they never match.
            if entry.isValid, seen.insert(entry).inserted { entries.append(entry) }
        }
        return entries
    }
}
