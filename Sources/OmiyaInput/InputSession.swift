public struct InputSession {
    public enum Mode {
        case japanese
        case english
    }

    public enum Key: Equatable {
        case text(String)
        case space
        case enter
        case escape
        case delete
        case katakana
        case nextCandidate
        case previousCandidate
        case nextSegment
        case previousSegment
        case expandSegment
        case shrinkSegment
    }

    public enum Action: Equatable {
        case passThrough
        case mark(String)
        case markConversion(ConversionPresentation)
        case commit(String)
        /// Commits the first string, then starts a new marked composition with the second.
        case commitAndMark(String, String)
        case requestConversion(String)
    }

    public private(set) var mode: Mode = .japanese
    private var romaji = Romaji()
    private var katakana = false
    private let converter: (any KanaKanjiConverter)?
    private var conversion: ActiveConversion?

    public init(converter: (any KanaKanjiConverter)? = nil) {
        self.converter = converter
    }

    public mutating func changeMode(to mode: Mode) -> Action {
        guard mode != self.mode else { return .passThrough }
        self.mode = mode
        return cancelComposition()
    }

    /// Switches mode from the keyboard (JIS かな / 英数 keys). Like the standard IME, pending text is committed.
    public mutating func switchModeByKey(to mode: Mode) -> Action {
        self.mode = mode
        return finishComposition()
    }

    public mutating func finishComposition() -> Action {
        guard !romaji.isEmpty else { return .passThrough }
        let text = conversion?.text ?? display(romaji.resolvedText)
        reset()
        return .commit(text)
    }

    public mutating func handle(_ key: Key) -> Action {
        guard mode == .japanese else { return .passThrough }

        if conversion != nil {
            switch key {
            case .enter:
                return finishComposition()
            case .escape:
                conversion = nil
                return .mark(display(romaji.markedText))
            case .text(let text):
                guard Self.asciiInput(text) != nil else { return .passThrough }
                // Like the standard IME: typing after a conversion commits it and starts new input.
                guard case .commit(let converted) = finishComposition() else { return .passThrough }
                guard case .mark(let marked) = type(text) else { return .commit(converted) }
                return .commitAndMark(converted, marked)
            case .delete, .katakana:
                conversion = nil
            default:
                return navigateConversion(key)
            }
        }

        switch key {
        case .text(let text):
            return type(text)
        case .space:
            if romaji.isEmpty { return .commit("　") }
            let reading = romaji.resolvedText
            conversion = ActiveConversion(converter?.convert(reading, segmentLengths: nil), reading: reading)
            return conversion.map { .markConversion($0.presentation) } ?? .requestConversion(reading)
        case .enter:
            return finishComposition()
        case .escape:
            return cancelComposition()
        case .delete:
            guard !romaji.isEmpty else { return .passThrough }
            romaji.deleteLast()
            if romaji.isEmpty { katakana = false }
            return .mark(display(romaji.markedText))
        case .katakana:
            guard !romaji.isEmpty else { return .passThrough }
            romaji.finalizePending()
            katakana = true
            return .mark(display(romaji.markedText))
        case .nextCandidate, .previousCandidate, .nextSegment, .previousSegment, .expandSegment, .shrinkSegment:
            return .passThrough
        }
    }

    public mutating func selectCandidate(_ text: String, confirm: Bool) -> Action {
        guard conversion?.selectCandidate(text) == true else { return .passThrough }
        if confirm { return finishComposition() }
        return conversion.map { .markConversion($0.presentation) } ?? .passThrough
    }

    private mutating func navigateConversion(_ key: Key) -> Action {
        guard var active = conversion else { return .passThrough }
        switch key {
        case .space where !active.isListVisible: active.showList()
        case .space, .nextCandidate: active.moveCandidate(by: 1)
        case .previousCandidate: active.moveCandidate(by: -1)
        case .nextSegment: active.moveSegment(by: 1)
        case .previousSegment: active.moveSegment(by: -1)
        case .expandSegment, .shrinkSegment:
            if let converter {
                active.resize(by: key == .expandSegment ? 1 : -1,
                              reading: romaji.resolvedText, converter: converter)
            }
        default: return .passThrough
        }
        conversion = active
        return .markConversion(active.presentation)
    }

    private static func asciiInput(_ text: String) -> Unicode.Scalar? {
        guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first,
              (0x21...0x7E).contains(scalar.value) else { return nil }
        return scalar
    }

    private mutating func type(_ text: String) -> Action {
        guard let scalar = Self.asciiInput(text) else { return .passThrough }

        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A:
            romaji.appendLetter(Character(text.lowercased()))
        case 0x27 where romaji.pending == "n":
            romaji.appendLetter("'")
        default:
            romaji.appendSymbol(scalar)
        }
        return .mark(display(romaji.markedText))
    }

    private func display(_ text: String) -> String {
        guard katakana else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            if (0x3041...0x3096).contains(scalar.value),
               let converted = Unicode.Scalar(scalar.value + 0x60) {
                return converted
            }
            return scalar
        }))
    }

    private mutating func cancelComposition() -> Action {
        guard !romaji.isEmpty else { return .passThrough }
        reset()
        return .mark("")
    }

    private mutating func reset() {
        romaji = Romaji()
        katakana = false
        conversion = nil
    }
}
