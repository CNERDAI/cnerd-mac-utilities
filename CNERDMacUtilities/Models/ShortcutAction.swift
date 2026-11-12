import Carbon.HIToolbox
import Foundation

/// Window actions that can have a global keyboard shortcut.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case maximize
    case left
    case right
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maximize: "Maximize / Restore"
        case .left: "Move Window Left"
        case .right: "Move Window Right"
        case .center: "Center Window"
        }
    }

    var position: WindowPosition {
        switch self {
        case .maximize: .maximize
        case .left: .leftHalf
        case .right: .rightHalf
        case .center: .center
        }
    }

    /// Stable identifier used when registering the hot key with the system.
    var hotKeyID: UInt32 {
        switch self {
        case .maximize: 1
        case .left: 2
        case .right: 3
        case .center: 4
        }
    }

    /// Control-Option plus a key. macOS does not use these by default
    /// (its own tiling shortcuts use the Globe key).
    var defaultCombo: KeyCombo {
        let modifiers = UInt32(controlKey | optionKey)
        switch self {
        case .maximize: return KeyCombo(keyCode: UInt32(kVK_UpArrow), carbonModifiers: modifiers, keyLabel: "↑")
        case .left: return KeyCombo(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: modifiers, keyLabel: "←")
        case .right: return KeyCombo(keyCode: UInt32(kVK_RightArrow), carbonModifiers: modifiers, keyLabel: "→")
        case .center: return KeyCombo(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: modifiers, keyLabel: "C")
        }
    }

    static var defaultShortcuts: [ShortcutAction: KeyCombo] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.defaultCombo) })
    }
}
