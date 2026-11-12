import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: one key plus modifier keys.
/// Modifiers are stored in Carbon format because the system hot key API uses it.
struct KeyCombo: Codable, Hashable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    /// Readable name of the key, for example "←" or "C".
    let keyLabel: String

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// Builds a combo from a key-down event.
    /// Returns nil unless Control, Option, or Command is held, so plain typing is never captured.
    init?(event: NSEvent) {
        let modifiers = KeyCombo.carbonModifiers(from: event.modifierFlags)
        let required = UInt32(controlKey | optionKey | cmdKey)
        guard modifiers & required != 0 else { return nil }
        let code = UInt32(event.keyCode)
        self.init(
            keyCode: code,
            carbonModifiers: modifiers,
            keyLabel: KeyCombo.label(forKeyCode: code, characters: event.charactersIgnoringModifiers)
        )
    }

    /// For example "⌃⌥←".
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    static func label(forKeyCode keyCode: UInt32, characters: String?) -> String {
        if let special = specialKeyLabels[Int(keyCode)] { return special }
        if let characters, !characters.isEmpty { return characters.uppercased() }
        return "Key \(keyCode)"
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
