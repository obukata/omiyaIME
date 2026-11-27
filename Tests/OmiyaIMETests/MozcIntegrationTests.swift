import Foundation
import XCTest
import OmiyaInput
@testable import OmiyaIME

final class MozcIntegrationTests: XCTestCase {
    func testPackagedConverterHandlesConversionAndResize() throws {
        guard let path = ProcessInfo.processInfo.environment["OMIYAIME_TEST_BUNDLE"] else {
            throw XCTSkip("Set OMIYAIME_TEST_BUNDLE to a development app with Mozc.")
        }
        let bundle = try XCTUnwrap(Bundle(path: path))
        let converter = try XCTUnwrap(MozcConverter(bundle: bundle))
        let reading = "きょうはいいてんきです"
        let original = try XCTUnwrap(converter.convert(reading, segmentLengths: nil))
        XCTAssertGreaterThanOrEqual(original.count, 2)
        guard original.count >= 2 else { return }

        XCTAssertTrue(original.map(\.reading).joined() == reading)
        XCTAssertTrue(original.flatMap(\.candidates).contains { $0.contains("今日") })
        let repeated = try XCTUnwrap(converter.convert(reading, segmentLengths: nil))
        XCTAssertTrue(repeated.map(\.candidates) == original.map(\.candidates))

        var lengths = original.map { $0.reading.unicodeScalars.count }
        lengths[0] += 1
        lengths[1] -= 1
        lengths.removeAll { $0 == 0 }
        let resized = try XCTUnwrap(converter.convert(reading, segmentLengths: lengths))
        XCTAssertEqual(resized.map { $0.reading.unicodeScalars.count }, lengths)

        var session = InputSession(converter: converter)
        for letter in "kyouhaiitenkidesu" { _ = session.handle(.text(String(letter))) }
        guard case .markConversion(let first) = session.handle(.space) else {
            XCTFail("An explicit conversion should mark the text")
            return
        }
        XCTAssertTrue(first.visibleCandidates.isEmpty)
        guard case .markConversion(let listed) = session.handle(.space) else {
            XCTFail("A second Space should show candidates")
            return
        }
        XCTAssertFalse(listed.visibleCandidates.isEmpty)
        XCTAssertTrue(session.handle(.enter) == .commit(listed.text))

        let entry = UserDictionaryEntry(reading: reading, phrase: "検証用の優先語")
        let withDictionary = UserDictionaryConverter(base: converter, entries: { [entry] })
        var dictionarySession = InputSession(converter: withDictionary)
        for letter in "kyouhaiitenkidesu" { _ = dictionarySession.handle(.text(String(letter))) }
        guard case .markConversion(let registered) = dictionarySession.handle(.space) else {
            XCTFail("The registered entry should convert")
            return
        }
        XCTAssertTrue(registered.text == entry.phrase)
        XCTAssertTrue(dictionarySession.handle(.enter) == .commit(entry.phrase))
    }

    func testSymbolsAreOfferedAfterRegularCandidatesWithoutEmoji() throws {
        guard let path = ProcessInfo.processInfo.environment["OMIYAIME_TEST_BUNDLE"] else {
            throw XCTSkip("Set OMIYAIME_TEST_BUNDLE to a development app with Mozc.")
        }
        let converter = try XCTUnwrap(MozcConverter(bundle: try XCTUnwrap(Bundle(path: path))))
        var session = InputSession(converter: converter)
        for letter in "enn" { _ = session.handle(.text(String(letter))) }
        _ = session.handle(.space)
        guard case .markConversion(let yen) = session.handle(.space) else {
            XCTFail("A second Space should show candidates")
            return
        }
        XCTAssertNotEqual(yen.visibleCandidates.first, "¥")
        XCTAssertTrue(yen.visibleCandidates.contains("¥"))

        var weather = InputSession(converter: converter)
        for letter in "tenki" { _ = weather.handle(.text(String(letter))) }
        _ = weather.handle(.space)
        guard case .markConversion(let listed) = weather.handle(.space) else {
            XCTFail("A second Space should show candidates")
            return
        }
        XCTAssertFalse(listed.visibleCandidates.contains("☔"))
    }
}
