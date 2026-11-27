import Foundation
import XCTest
@testable import OmiyaInput

final class UserDictionaryTests: XCTestCase {
    func testPersistenceAndFailedSavePreservesTheExistingDictionary() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appending(path: "user-dictionary.json")
        var file = try UserDictionaryFile(location: location)
        XCTAssertTrue(file.entries.isEmpty)

        let entries = [
            UserDictionaryEntry(reading: "みほん", phrase: "見本"),
            UserDictionaryEntry(reading: "みほん", phrase: "模範")
        ]
        try file.save(entries)
        let original = try Data(contentsOf: location)

        XCTAssertThrowsError(try file.save(entries + entries))
        XCTAssertThrowsError(try file.save([UserDictionaryEntry(reading: "みほん", phrase: "😀")]))
        XCTAssertTrue(file.entries == entries)
        XCTAssertTrue(try Data(contentsOf: location) == original)
        XCTAssertTrue(try UserDictionaryFile(location: location).entries == entries)
    }

    func testFullReadingAndCrossBoundaryEntriesBecomeFirstCandidates() throws {
        let base = DictionaryFixture()
        let entry = UserDictionaryEntry(reading: "ほんて", phrase: "本手")
        let converter = UserDictionaryConverter(base: base, entries: { [entry] })
        let result = try XCTUnwrap(converter.convert("みほんてんき", segmentLengths: nil))
        XCTAssertTrue(result.map(\.reading) == ["み", "ほんて", "んき"])
        XCTAssertTrue(CandidatePolicy.ranked(result[1]).first == "本手")
        XCTAssertEqual(base.requests.last!, [1, 3, 2])

        let whole = UserDictionaryEntry(reading: "みほんてんき", phrase: "見本天気")
        let wholeConverter = UserDictionaryConverter(base: base, entries: { [whole] })
        let joined = try XCTUnwrap(wholeConverter.convert("みほんてんき", segmentLengths: nil))
        XCTAssertEqual(joined.count, 1)
        XCTAssertTrue(CandidatePolicy.ranked(joined[0]).first == "見本天気")
    }

    func testExplicitResizeTakesPriorityOverPromotedSegmentation() throws {
        let base = DictionaryFixture()
        let entry = UserDictionaryEntry(reading: "みほんてんき", phrase: "見本天気")
        let converter = UserDictionaryConverter(base: base, entries: { [entry] })
        let result = try XCTUnwrap(converter.convert("みほんてんき", segmentLengths: [3, 3]))
        XCTAssertEqual(result.map { $0.reading.unicodeScalars.count }, [3, 3])
        XCTAssertEqual(base.requests.count, 1)
    }
}

private final class DictionaryFixture: KanaKanjiConverter {
    var requests: [[Int]?] = []

    func convert(_ reading: String, segmentLengths: [Int]?) -> [ConversionSegment]? {
        requests.append(segmentLengths)
        switch segmentLengths {
        case [1, 3, 2]:
            return [ConversionSegment(reading: "み", candidates: ["実"]),
                    ConversionSegment(reading: "ほんて", candidates: ["本て"]),
                    ConversionSegment(reading: "んき", candidates: ["んき"])]
        case [6]:
            return nil
        default:
            return [ConversionSegment(reading: "みほん", candidates: ["見本"]),
                    ConversionSegment(reading: "てんき", candidates: ["天気"])]
        }
    }
}
