import Foundation
import SQLite3
import XCTest
import OmiyaInput

final class SystemUserDictionaryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// Builds a store shaped like macOS's TextReplacements.db with fictional entries.
    private func makeStore(_ rows: [(String, String, Int)]) throws -> URL {
        let url = directory.appending(path: "TextReplacements.db")
        try? FileManager.default.removeItem(at: url)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var sql = "CREATE TABLE ZTEXTREPLACEMENTENTRY (Z_PK INTEGER PRIMARY KEY, ZWASDELETED INTEGER, ZPHRASE VARCHAR, ZSHORTCUT VARCHAR);"
        for (index, row) in rows.enumerated() {
            sql += "INSERT INTO ZTEXTREPLACEMENTENTRY VALUES (\(index + 1), \(row.2), '\(row.1)', '\(row.0)');"
        }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        return url
    }

    func testReadsActiveJapaneseEntriesOnly() throws {
        let url = try makeStore([
            ("てすとご", "試験語", 0),
            ("けしたご", "消した語", 1),
            ("omw", "On my way!", 0),
            ("てすとご", "試験語", 0),
            ("にこ", "😀", 0)
        ])
        XCTAssertEqual(SystemUserDictionary(location: url).entries,
                       [UserDictionaryEntry(reading: "てすとご", phrase: "試験語")])
    }

    func testRereadsAfterTheStoreChanges() throws {
        let url = try makeStore([("てすとご", "試験語", 0)])
        let dictionary = SystemUserDictionary(location: url)
        XCTAssertEqual(dictionary.entries.count, 1)
        _ = try makeStore([("てすとご", "試験語", 0), ("かくにん", "確認語", 0)])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        XCTAssertEqual(dictionary.entries.count, 2)
    }

    func testMissingOrUnreadableStoreGivesNoEntries() throws {
        XCTAssertEqual(SystemUserDictionary(location: directory.appending(path: "none.db")).entries, [])
        let broken = directory.appending(path: "broken.db")
        try Data("not a database".utf8).write(to: broken)
        XCTAssertEqual(SystemUserDictionary(location: broken).entries, [])
    }
}
