import XCTest
import OmiyaInput

final class InputSessionTests: XCTestCase {
    func testCommonRomajiAndAliases() {
        let examples = [
            ("kyou", "きょう"), ("gakkou", "がっこう"), ("konnnichiha", "こんにちは"), ("funniki", "ふんいき"), ("konnyaku", "こんやく"),
            ("kan'i", "かんい"), ("kon", "こん"), ("nyu-su", "にゅーす"),
            ("matcha", "まっちゃ"), ("zhzjzkzl", "←↓↑→"), ("ti", "ち"), ("fa", "ふぁ"), ("xyo", "ょ")
        ]
        for (index, (input, output)) in examples.enumerated() {
            var session = InputSession()
            _ = type(input, in: &session)
            XCTAssertTrue(session.handle(.enter) == .commit(output), "Romanization case \(index)")
        }
    }

    func testPendingLettersCanBeEditedOrCommitted() {
        var session = InputSession()
        XCTAssertTrue(type("sh", in: &session) == .mark("sh"))
        XCTAssertTrue(session.handle(.delete) == .mark("s"))
        XCTAssertTrue(session.handle(.text("i")) == .mark("し"))
        XCTAssertTrue(session.handle(.delete) == .mark(""))
        XCTAssertTrue(session.handle(.delete) == .passThrough)
        XCTAssertTrue(session.handle(.text("k")) == .mark("k"))
        XCTAssertTrue(session.handle(.enter) == .commit("k"))
        XCTAssertTrue(session.handle(.enter) == .passThrough)
    }

    func testLeftoverLettersStayHalfWidthAndDigitsAreFullWidth() {
        var session = InputSession()
        XCTAssertTrue(type("kyouhaiitn", in: &session) == .mark("きょうはいいtn"))
        XCTAssertTrue(type("2", in: &session) == .mark("きょうはいいtん２"))
        XCTAssertTrue(session.handle(.enter) == .commit("きょうはいいtん２"))
    }

    func testDeletingNAndReusingLeftoverLetters() {
        var session = InputSession()
        XCTAssertTrue(type("iitn", in: &session) == .mark("いいtn"))
        XCTAssertTrue(session.handle(.text("n")) == .mark("いいtん"))
        XCTAssertTrue(session.handle(.delete) == .mark("いいt"))
        XCTAssertTrue(session.handle(.text("e")) == .mark("いいて"))
        XCTAssertTrue(type("tn", in: &session) == .mark("いいてtn"))
        XCTAssertTrue(session.handle(.delete) == .mark("いいてt"))
        XCTAssertTrue(session.handle(.text("e")) == .mark("いいてて"))
    }

    func testShiftLetterSwitchesToEnglishWithMarkedText() {
        var session = InputSession()
        XCTAssertTrue(type("kana", in: &session) == .mark("かな"))
        XCTAssertTrue(session.handle(.text("A")) == .mark("かなA"))
        XCTAssertEqual(session.mode, .english)
        XCTAssertTrue(type("pple", in: &session) == .mark("かなApple"))
        XCTAssertTrue(session.handle(.space) == .mark("かなApple "))
        XCTAssertTrue(session.handle(.delete) == .mark("かなApple"))
        XCTAssertTrue(session.handle(.enter) == .commit("かなApple"))
        XCTAssertTrue(session.handle(.text("x")) == .passThrough)

        var other = InputSession()
        _ = other.handle(.text("O"))
        XCTAssertTrue(other.handle(.nextSegment) == .commitThenPassThrough("O"))
        _ = other.switchModeByKey(to: .japanese)
        _ = other.handle(.text("Q"))
        XCTAssertTrue(other.handle(.escape) == .mark(""))
    }

    func testModeSwitchKeepsMarkedTextAndContinues() {
        var session = InputSession()
        XCTAssertTrue(type("IME", in: &session) == .mark("IME"))
        // かな key, or macOS switching the mode itself: the text stays marked.
        XCTAssertTrue(session.switchModeByKey(to: .japanese) == .mark("IME"))
        XCTAssertTrue(type("desu", in: &session) == .mark("IMEです"))
        XCTAssertTrue(session.changeMode(to: .english) == .mark("IMEです"))
        XCTAssertTrue(type("ok", in: &session) == .mark("IMEですok"))
        XCTAssertTrue(session.changeMode(to: .japanese) == .mark("IMEですok"))
        // English letters never turn back into romaji, even after deleting.
        XCTAssertTrue(session.handle(.delete) == .mark("IMEですo"))
        XCTAssertTrue(type("a", in: &session) == .mark("IMEですoあ"))
        XCTAssertTrue(session.handle(.enter) == .commit("IMEですoあ"))

        var pending = InputSession()
        _ = type("k", in: &pending)
        XCTAssertTrue(pending.switchModeByKey(to: .english) == .mark("k"))
        XCTAssertTrue(type("a", in: &pending) == .mark("ka"))
    }

    func testBracketsBecomeJapaneseQuotes() {
        var session = InputSession()
        XCTAssertTrue(type("[a]", in: &session) == .mark("「あ」"))
        XCTAssertTrue(type("/", in: &session) == .mark("「あ」・"))
    }

    func testJapanesePunctuationAndWidthsRemainMarkedUntilEnter() {
        var session = InputSession()
        XCTAssertTrue(type("kana,", in: &session) == .mark("かな、"))
        XCTAssertTrue(type("1!.", in: &session) == .mark("かな、１！。"))
        XCTAssertTrue(session.handle(.enter) == .commit("かな、１！。"))
        XCTAssertTrue(session.handle(.space) == .commit("　"))
    }

    func testConversionRequestKeepsReadingUntilReturn() {
        var session = InputSession()
        _ = type("tenki", in: &session)
        XCTAssertTrue(session.handle(.space) == .requestConversion("てんき"))
        XCTAssertTrue(session.handle(.space) == .requestConversion("てんき"))
        XCTAssertTrue(session.handle(.enter) == .commit("てんき"))
    }

    func testKatakanaRemainsMarkedAndCanBeCancelled() {
        var session = InputSession()
        _ = type("pan", in: &session)
        XCTAssertTrue(session.handle(.katakana) == .mark("パン"))
        XCTAssertTrue(session.handle(.text("a")) == .mark("パンア"))
        XCTAssertTrue(session.handle(.enter) == .commit("パンア"))
        _ = type("kana", in: &session)
        XCTAssertTrue(session.handle(.katakana) == .mark("カナ"))
        XCTAssertTrue(session.handle(.escape) == .mark(""))
        XCTAssertTrue(session.handle(.enter) == .passThrough)
        XCTAssertTrue(type("kana", in: &session) == .mark("かな"))
    }

    func testEnglishModeLetsHostHandleInput() {
        var session = InputSession()
        XCTAssertTrue(session.changeMode(to: .japanese) == .passThrough)
        XCTAssertTrue(session.changeMode(to: .english) == .passThrough)
        XCTAssertTrue(session.handle(.text("a")) == .passThrough)
        XCTAssertTrue(session.handle(.text("9")) == .passThrough)
        XCTAssertTrue(session.handle(.space) == .passThrough)
        XCTAssertTrue(session.handle(.katakana) == .passThrough)
        XCTAssertTrue(session.changeMode(to: .japanese) == .passThrough)
        XCTAssertTrue(type("kana", in: &session) == .mark("かな"))
    }

    func testClientsDoNotShareComposition() {
        var first = InputSession()
        var second = InputSession()
        _ = type("kana", in: &first)
        XCTAssertTrue(second.finishComposition() == .passThrough)
        XCTAssertTrue(first.finishComposition() == .commit("かな"))
        XCTAssertTrue(first.finishComposition() == .passThrough)
    }

    func testNonRomanInputPassesThroughWithoutChangingMarkedText() {
        var session = InputSession()
        _ = type("ka", in: &session)
        XCTAssertTrue(session.handle(.text("abc")) == .passThrough)
        XCTAssertTrue(session.handle(.text("é")) == .passThrough)
        XCTAssertTrue(session.handle(.text("\u{F702}")) == .passThrough)
        XCTAssertTrue(session.finishComposition() == .commit("か"))
    }

    private func type(_ text: String, in session: inout InputSession) -> InputSession.Action {
        text.reduce(.passThrough) { _, key in session.handle(.text(String(key))) }
    }

    func testModeKeysKeepUnconvertedText() {
        var session = InputSession(converter: nil)
        _ = type("ka", in: &session)
        XCTAssertTrue(session.switchModeByKey(to: .english) == .mark("か"))
        XCTAssertTrue(session.mode == .english)
        XCTAssertTrue(session.handle(.enter) == .commit("か"))
        XCTAssertTrue(session.handle(.text("a")) == .passThrough)
        XCTAssertTrue(session.switchModeByKey(to: .japanese) == .passThrough)
        XCTAssertTrue(session.handle(.text("a")) == .mark("あ"))
    }
}
