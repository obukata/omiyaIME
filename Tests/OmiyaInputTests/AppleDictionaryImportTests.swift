import Foundation
import XCTest
import OmiyaInput

final class AppleDictionaryImportTests: XCTestCase {
    func testBothPlistFormatsPreserveRegistrationOrder() throws {
        let rows = [
            ["shortcut": "みほん", "phrase": "見本"],
            ["shortcut": "みほん", "phrase": "模範", "unknown": "ignored"]
        ]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let data = try PropertyListSerialization.data(fromPropertyList: rows, format: format, options: 0)
            let preview = try AppleDictionaryImport(data: data)
            XCTAssertTrue(preview.entries.map(\.phrase) == ["見本", "模範"])
            XCTAssertTrue(preview.entries.allSatisfy { $0.reading == "みほん" })
            XCTAssertTrue(preview.issues.isEmpty)
        }
    }

    func testIssuesUseRowNumbersAndKeepValidRows() throws {
        let rows: [Any] = [
            ["shortcut": "みほん", "phrase": "見本"],
            ["shortcut": "みほん", "phrase": "見本"],
            ["shortcut": " ", "phrase": "見本"],
            ["shortcut": "みほん", "phrase": "😊"],
            ["shortcut": "みほん", "phrase": "Example"],
            ["shortcut": 1, "phrase": "見本"]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: rows, format: .xml, options: 0)
        let preview = try AppleDictionaryImport(data: data)
        XCTAssertEqual(preview.entries.count, 1)
        XCTAssertEqual(preview.issues.map(\.row), [2, 3, 4, 5, 6])
        XCTAssertEqual(preview.issues.map(\.reason), [.duplicate, .empty, .excludedCandidate,
                                                      .excludedCandidate, .invalidFields])
    }

    func testEmptyArrayAndInvalidFile() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [String](), format: .xml, options: 0)
        XCTAssertTrue(try AppleDictionaryImport(data: data).entries.isEmpty)
        XCTAssertThrowsError(try AppleDictionaryImport(data: Data()))
        let wrongRoot = try PropertyListSerialization.data(fromPropertyList: ["shortcut": "value"],
                                                           format: .xml, options: 0)
        XCTAssertThrowsError(try AppleDictionaryImport(data: wrongRoot))
    }
}
