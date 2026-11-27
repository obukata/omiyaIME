import AppKit
import Carbon
import InputMethodKit
import OmiyaInput

@objc(OmiyaInputController)
final class InputController: IMKInputController, @unchecked Sendable {
    // InputMethodKit's Objective-C callbacks drive this session on AppKit's main thread.
    private static let japaneseModeID = "com.apple.inputmethod.Japanese"
    private static let romanModeID = "com.apple.inputmethod.Roman"
    private static let japaneseSourceID = "jp.omiyaime.inputmethod.omiyaIME.Japanese"
    private static let romanSourceID = "jp.omiyaime.inputmethod.omiyaIME.Roman"
    private static let currentSelection = NSRange(location: NSNotFound, length: 0)

    private lazy var session: InputSession = {
        let converter = MozcConverter(bundle: .main).map { base in
            UserDictionaryConverter(base: base) {
                MainActor.assumeIsolated { DictionaryPreferences.shared.conversionEntries }
            }
        }
        return InputSession(converter: converter)
    }()
    @MainActor private lazy var candidateWindow: CandidateWindow = {
        let window = CandidateWindow()
        window.onSelect = { [weak self] text in
            guard let self, let client = self.client() else { return }
            _ = self.apply(self.session.selectCandidate(text, confirm: true), to: client)
        }
        return window
    }()
    private var isShowingCandidates = false

    override func activateServer(_ sender: Any!) {
        guard Thread.isMainThread, let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return }
        let sourceID = Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
        if sourceID == Self.japaneseSourceID || sourceID == Self.romanSourceID {
            setValue(sourceID, forTag: Int(kTextServiceInputModePropertyTag), client: sender)
        }
    }

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        guard Thread.isMainThread else { return }
        guard tag == Int(kTextServiceInputModePropertyTag) else {
            super.setValue(value, forTag: tag, client: sender)
            return
        }

        let mode: InputSession.Mode
        switch value as? String {
        case Self.japaneseModeID, Self.japaneseSourceID: mode = .japanese
        case Self.romanModeID, Self.romanSourceID: mode = .english
        default: return
        }
        let action = session.changeMode(to: mode)
        if let client = (sender as? any IMKTextInput) ?? self.client() {
            _ = apply(action, to: client)
        }
    }

    override func value(forTag tag: Int, client sender: Any!) -> Any! {
        guard Thread.isMainThread else { return nil }
        if tag == Int(kTextServiceInputModePropertyTag) {
            return session.mode == .japanese ? Self.japaneseModeID : Self.romanModeID
        }
        return super.value(forTag: tag, client: sender)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard Thread.isMainThread, let event, event.type == .keyDown,
              let client = sender as? any IMKTextInput
        else { return false }
        if let target = Self.modeKey(for: event) {
            _ = apply(session.switchModeByKey(to: target), to: client)
            client.selectMode(target == .japanese ? Self.japaneseSourceID : Self.romanSourceID)
            return true
        }
        guard let key = Self.key(for: event) else { return false }
        return apply(session.handle(key), to: client)
    }

    override func commitComposition(_ sender: Any!) {
        guard Thread.isMainThread, let client = (sender as? any IMKTextInput) ?? self.client() else { return }
        _ = apply(session.finishComposition(), to: client)
    }

    override func deactivateServer(_ sender: Any!) {
        guard Thread.isMainThread else { return }
        hideCandidates()
        super.deactivateServer(sender)
    }

    override func menu() -> NSMenu! {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated {
            let menu = NSMenu()
            let item = NSMenuItem(title: "おみやIMEの設定…", action: #selector(showPreferences(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return MainThreadMenu(menu)
        }.menu
    }

    // IMK's menu callback is synchronous, and the caller remains on the main thread.
    private struct MainThreadMenu: @unchecked Sendable {
        let menu: NSMenu
        init(_ menu: NSMenu) { self.menu = menu }
    }

    override func showPreferences(_ sender: Any!) {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { DictionaryPreferences.shared.show() }
    }

    /// JIS keyboards: かな switches to Japanese, 英数 to English.
    private static func modeKey(for event: NSEvent) -> InputSession.Mode? {
        switch Int(event.keyCode) {
        case kVK_JIS_Kana: return .japanese
        case kVK_JIS_Eisu: return .english
        default: return nil
        }
    }

    private static func key(for event: NSEvent) -> InputSession.Key? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .control, event.charactersIgnoringModifiers?.lowercased() == "k" {
            return .katakana
        }
        guard modifiers.subtracting(.shift).isEmpty else { return nil }

        let code = Int(event.keyCode)
        if modifiers == .shift {
            switch code {
            case kVK_LeftArrow: return .shrinkSegment
            case kVK_RightArrow: return .expandSegment
            case kVK_Space: return .previousCandidate
            // Shift+Return commits pending text like Return; apps that treat it as a newline
            // would otherwise drop the marked text.
            case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
            default: break
            }
        }
        if modifiers.isEmpty {
            switch code {
            case kVK_Space: return .space
            case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
            case kVK_Escape: return .escape
            case kVK_Delete: return .delete
            case kVK_LeftArrow: return .previousSegment
            case kVK_RightArrow: return .nextSegment
            case kVK_UpArrow: return .previousCandidate
            case kVK_DownArrow: return .nextCandidate
            default: break
            }
        }
        return event.characters.map(InputSession.Key.text)
    }

    private func apply(_ action: InputSession.Action, to client: any IMKTextInput) -> Bool {
        switch action {
        case .passThrough:
            return false
        case .mark(let text):
            hideCandidates()
            client.setMarkedText(
                text,
                selectionRange: NSRange(location: text.utf16.count, length: 0),
                replacementRange: Self.currentSelection
            )
        case .markConversion(let conversion):
            let range = NSRange(location: conversion.selection.lowerBound, length: conversion.selection.count)
            let marked = NSMutableAttributedString(
                string: conversion.text, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
            )
            marked.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: range)
            client.setMarkedText(marked, selectionRange: range, replacementRange: Self.currentSelection)
            showCandidates(for: conversion, client: client)
        case .commit(let text):
            hideCandidates()
            client.insertText(text, replacementRange: Self.currentSelection)
        case .commitAndMark(let text, let marked):
            hideCandidates()
            client.insertText(text, replacementRange: Self.currentSelection)
            client.setMarkedText(
                marked,
                selectionRange: NSRange(location: marked.utf16.count, length: 0),
                replacementRange: Self.currentSelection
            )
        case .requestConversion:
            // The input remains marked while the conversion engine is unavailable.
            break
        }
        return true
    }

    private func showCandidates(for conversion: ConversionPresentation, client: any IMKTextInput) {
        guard !conversion.visibleCandidates.isEmpty else {
            hideCandidates()
            return
        }
        var anchor = NSRect.zero
        _ = client.attributes(forCharacterIndex: conversion.selection.lowerBound, lineHeightRectangle: &anchor)
        if anchor == .zero { anchor = NSRect(origin: NSEvent.mouseLocation, size: .zero) }
        MainActor.assumeIsolated {
            candidateWindow.show(candidates: conversion.visibleCandidates,
                                 selected: conversion.selectedCandidate, anchor: anchor)
        }
        isShowingCandidates = true
    }

    private func hideCandidates() {
        guard isShowingCandidates else { return }
        isShowingCandidates = false
        MainActor.assumeIsolated { candidateWindow.hide() }
    }
}
