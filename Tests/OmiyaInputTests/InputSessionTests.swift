import XCTest
import OmiyaInput

final class InputSessionTests: XCTestCase {
    func testCommonRomajiAndAliases() {
        let examples = [
            ("kyou", "きょう"), ("gakkou", "がっこう"), ("konnichiha", "こんにちは"),
            ("kan'i", "かんい"), ("kon", "こん"), ("nyu-su", "にゅーす"),
            ("MATCHA", "まっちゃ"), ("ti", "ち"), ("fa", "ふぁ"), ("xyo", "ょ")
        ]
        for (index, (input, output)) in examples.enumerated() {
            var session = InputSession()
            _ = type(input, in: &session)
            XCTAssertTrue(session.handle(.enter) == .commit(output), "Romanization case \(index)")
        }
    }

    func testPendingLettersCanBeEditedOrCommitted() {
        var session = InputSession()
        XCTAssertTrue(type("sh", in: &session) == .mark("ｓｈ"))
        XCTAssertTrue(session.handle(.delete) == .mark("ｓ"))
        XCTAssertTrue(session.handle(.text("i")) == .mark("し"))
        XCTAssertTrue(session.handle(.delete) == .mark(""))
        XCTAssertTrue(session.handle(.delete) == .passThrough)
        XCTAssertTrue(session.handle(.text("k")) == .mark("ｋ"))
        XCTAssertTrue(session.handle(.enter) == .commit("ｋ"))
        XCTAssertTrue(session.handle(.enter) == .passThrough)
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
        _ = type("kana", in: &session)
        XCTAssertTrue(session.changeMode(to: .japanese) == .passThrough)
        XCTAssertTrue(session.changeMode(to: .english) == .mark(""))
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

    func testModeKeysCommitPendingTextAndSwitch() {
        var session = InputSession()
        _ = session.handle(.text("k"))
        _ = session.handle(.text("a"))
        XCTAssertTrue(session.switchModeByKey(to: .english) == .commit("か"))
        XCTAssertTrue(session.mode == .english)
        XCTAssertTrue(session.handle(.text("a")) == .passThrough)
        XCTAssertTrue(session.switchModeByKey(to: .japanese) == .passThrough)
        XCTAssertTrue(session.handle(.text("a")) == .mark("あ"))
    }
}
