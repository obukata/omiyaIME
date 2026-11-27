import XCTest
@testable import OmiyaInput

final class ConversionTests: XCTestCase {
    func testExplicitConversionAndCandidateNavigation() {
        let engine = FixtureConverter()
        var session = preparedSession(engine)
        XCTAssertTrue(engine.requests.isEmpty)

        let first = presentation(session.handle(.space))
        XCTAssertTrue(first?.text == "今日天気")
        XCTAssertTrue(first?.visibleCandidates.isEmpty == true)
        XCTAssertEqual(first?.selection, 0..<2)

        let listed = presentation(session.handle(.space))
        XCTAssertTrue(listed?.visibleCandidates == ["今日", "京", "きょう"])
        XCTAssertEqual(listed?.selectedCandidate, 0)
        XCTAssertEqual(presentation(session.handle(.nextCandidate))?.selectedCandidate, 1)
        XCTAssertEqual(presentation(session.handle(.previousCandidate))?.selectedCandidate, 0)
        XCTAssertEqual(presentation(session.handle(.nextSegment))?.selection, 2..<4)
        XCTAssertTrue(session.handle(.enter) == .commit("今日天気"))
        XCTAssertEqual(engine.requests.count, 1)
    }

    func testTypingAfterConversionCommitsItAndStartsNewInput() {
        var session = preparedSession(FixtureConverter())
        _ = session.handle(.space)
        XCTAssertTrue(session.handle(.text("a")) == .commitAndMark("今日天気", "あ"))
        XCTAssertTrue(session.handle(.text(".")) == .mark("あ。"))
        XCTAssertTrue(session.handle(.enter) == .commit("あ。"))
    }

    func testResizeKeepsTheReadingAndUnchangedSelections() {
        let engine = FixtureConverter()
        var session = preparedSession(engine)
        _ = session.handle(.space)
        _ = session.handle(.space)
        _ = session.handle(.nextSegment)
        _ = session.handle(.nextCandidate)
        _ = session.handle(.previousSegment)

        let expanded = presentation(session.handle(.expandSegment))
        XCTAssertTrue(expanded?.text == "今日手んき")
        XCTAssertEqual(engine.requests.last!, [4, 2])
        let shrunk = presentation(session.handle(.shrinkSegment))
        XCTAssertTrue(shrunk?.text == "今日天気")
        XCTAssertEqual(engine.requests.last!, [3, 3])
        _ = session.handle(.nextSegment)
        XCTAssertTrue(session.selectCandidate("転機", confirm: false) != .passThrough)
        XCTAssertTrue(session.handle(.enter) == .commit("今日転機"))
    }

    func testInvalidEngineDataKeepsTheReadingMarked() {
        var session = preparedSession(FixtureConverter(invalid: true))
        XCTAssertTrue(session.handle(.space) == .requestConversion("きょうてんき"))
        XCTAssertTrue(session.handle(.enter) == .commit("きょうてんき"))
    }

    func testEscapeReturnsToReadingAndThenClearsIt() {
        var session = preparedSession(FixtureConverter())
        _ = session.handle(.space)
        _ = session.handle(.space)
        XCTAssertTrue(session.handle(.escape) == .mark("きょうてんき"))
        XCTAssertTrue(session.handle(.escape) == .mark(""))
        XCTAssertTrue(session.handle(.enter) == .passThrough)
    }

    func testModeSwitchCommitsAnActiveConversion() {
        var session = preparedSession(FixtureConverter())
        guard case .markConversion(let conversion) = session.handle(.space) else {
            return XCTFail("Space should convert")
        }
        XCTAssertTrue(session.switchModeByKey(to: .english) == .commit(conversion.text))
        XCTAssertTrue(session.handle(.text("a")) == .passThrough)
    }

    func testWidthVariantsOfTheReadingComeLast() {
        let english = ConversionSegment(reading: "IME", candidates: ["IME", "ＩＭＥ"])
        XCTAssertEqual(CandidatePolicy.ranked(english), ["IME", "ＩＭＥ"])
        let digits = ConversionSegment(reading: "１２３", candidates: ["百二十三"])
        XCTAssertEqual(CandidatePolicy.ranked(digits), ["百二十三", "１２３", "123"])
        let kana = ConversionSegment(reading: "よみ", candidates: ["読み"])
        XCTAssertEqual(CandidatePolicy.ranked(kana), ["読み", "よみ"])
    }

    func testFilteringAndStablePriorityAcrossAllCandidateSources() {
        let segment = ConversionSegment(
            reading: "よみ",
            candidates: ["変換", "☺", "☻", "😀", "❤️", "1️⃣", "🇯🇵", "👩‍💻",
                         "Ａｐｐｌｅ", "café", "日😀本", "1", "１", "★", "ＩＴ企業",
                         "時計⌚︎", "候補", "変換"],
            userCandidates: ["候補", "😀", "test@example.com", "候補"]
        )
        // User-registered English text (e.g. an e-mail address) is kept; converter English is not.
        let expected = ["候補", "test@example.com", "変換", "1", "１", "★", "ＩＴ企業", "時計⌚︎", "よみ"]
        XCTAssertTrue(CandidatePolicy.ranked(segment) == expected)
        XCTAssertTrue(CandidatePolicy.ranked(segment) == expected)
    }

    func testFilteredCandidatesCannotBeDirectlyConfirmed() {
        var session = preparedSession(FixtureConverter())
        _ = session.handle(.space)
        _ = session.handle(.space)
        XCTAssertTrue(session.selectCandidate("☺", confirm: true) == .passThrough)
        XCTAssertTrue(session.selectCandidate("京", confirm: true) == .commit("京天気"))
    }

    private func preparedSession(_ converter: FixtureConverter) -> InputSession {
        var session = InputSession(converter: converter)
        for letter in "kyoutenki" { _ = session.handle(.text(String(letter))) }
        return session
    }

    private func presentation(_ action: InputSession.Action) -> ConversionPresentation? {
        guard case .markConversion(let value) = action else {
            XCTFail("Expected marked conversion")
            return nil
        }
        return value
    }
}

private final class FixtureConverter: KanaKanjiConverter {
    let invalid: Bool
    var requests: [[Int]?] = []

    init(invalid: Bool = false) {
        self.invalid = invalid
    }

    func convert(_ reading: String, segmentLengths: [Int]?) -> [ConversionSegment]? {
        requests.append(segmentLengths)
        if invalid { return [ConversionSegment(reading: "別の読み", candidates: ["誤り"])] }
        if segmentLengths == [4, 2] {
            return [ConversionSegment(reading: "きょうて", candidates: ["今日手"]),
                    ConversionSegment(reading: "んき", candidates: ["んき"])]
        }
        return [ConversionSegment(reading: "きょう", candidates: ["☺", "今日", "京"]),
                ConversionSegment(reading: "てんき", candidates: ["天気", "転機"])]
    }
}
