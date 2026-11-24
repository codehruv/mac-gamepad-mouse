import Carbon
import CoreGraphics

/// Posts synthetic arrow-key taps for D-pad → text navigation in any focused field.
final class KeyboardInjector {

    private let source = CGEventSource(stateID: .hidSystemState)
    private var modifierHolds = ModifierHolds()
    private var postedModifiers = Set<ShortcutModifier>()
    private let emit: (CGEvent) -> Void

    init(emit: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.emit = emit
    }

    func tapShortcut(_ shortcut: KeyShortcut) {
        guard let code = shortcut.keyCode else { return }
        let flags = modifierFlags(Set(shortcut.modifiers).union(modifierHolds.held))
        postKey(keyCode: CGKeyCode(code), keyDown: true, flags: flags)
        postKey(keyCode: CGKeyCode(code), keyDown: false, flags: flags)
    }

    func beginSwitcher(owner: String, shortcut: KeyShortcut) {
        for modifier in modifierHolds.acquire(owner: owner, modifiers: shortcut.modifiers) {
            postModifier(modifier, down: true)
        }
        tapShortcut(shortcut)
    }

    func endSwitcher(owner: String) {
        for modifier in modifierHolds.release(owner: owner) { postModifier(modifier, down: false) }
    }

    func releaseAllModifiers() {
        for modifier in modifierHolds.releaseAll() { postModifier(modifier, down: false) }
    }

    private func postModifier(_ modifier: ShortcutModifier, down: Bool) {
        let code: CGKeyCode
        switch modifier {
        case .command: code = CGKeyCode(kVK_Command)
        case .option: code = CGKeyCode(kVK_Option)
        case .control: code = CGKeyCode(kVK_Control)
        case .shift: code = CGKeyCode(kVK_Shift)
        }
        if down { postedModifiers.insert(modifier) } else { postedModifiers.remove(modifier) }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = modifierFlags(postedModifiers)
        emit(event)
    }

    private func modifierFlags(_ modifiers: Set<ShortcutModifier>) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
        return flags
    }

    enum Arrow {
        case left, right, up, down

        fileprivate var keyCode: CGKeyCode {
            switch self {
            case .left: return CGKeyCode(kVK_LeftArrow)
            case .right: return CGKeyCode(kVK_RightArrow)
            case .up: return CGKeyCode(kVK_UpArrow)
            case .down: return CGKeyCode(kVK_DownArrow)
            }
        }
    }

    /// One key-down / key-up pair (character-producing apps see a single arrow step).
    func tapArrow(_ arrow: Arrow) {
        postKey(keyCode: arrow.keyCode, keyDown: true)
        postKey(keyCode: arrow.keyCode, keyDown: false)
    }

    /// Sends text as HID Unicode key events (one `Character` at a time for compatibility).
    func typeText(_ text: String) {
        for ch in text {
            typeTextChunk(String(ch))
        }
    }

    private func typeTextChunk(_ text: String) {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }
        utf16.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            emit(down)
            guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
            emit(up)
        }
    }

    /// Laptop “delete” / backward delete (left of forward-delete on full keyboard).
    func tapBackwardDelete() {
        tapKeyCode(CGKeyCode(kVK_Delete))
    }

    func tapReturnKey() {
        tapKeyCode(CGKeyCode(kVK_Return))
    }

    private func tapKeyCode(_ code: CGKeyCode) {
        postKey(keyCode: code, keyDown: true)
        postKey(keyCode: code, keyDown: false)
    }

    private func postKey(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        emit(event)
    }
}
