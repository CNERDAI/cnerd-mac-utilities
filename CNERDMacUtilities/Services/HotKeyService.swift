import Carbon.HIToolbox
import Foundation

/// Global keyboard shortcuts through the system hot key API (RegisterEventHotKey).
/// This API is public, needs no extra permission, and uses no CPU while idle.
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    /// 'CNRD'
    private static let signature: OSType = 0x434E_5244

    private init() {}

    /// Registers a shortcut. Returns false when the system refuses it, for example
    /// because another app already owns the same combination.
    @discardableResult
    func register(id: UInt32, combo: KeyCombo, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }

        hotKeyRefs[id] = ref
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }

    fileprivate func handleHotKey(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 1, &spec, nil, &eventHandlerRef)
    }
}

/// C callback for hot key events. Carbon delivers these on the main thread.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        HotKeyService.shared.handleHotKey(id: id)
    }
    return noErr
}

/// Checks a shortcut against the shortcuts macOS itself has turned on
/// (Mission Control, Spotlight, screenshots, and so on).
enum SystemShortcuts {
    static func isUsedByMacOS(_ combo: KeyCombo) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return false }

        for entry in entries {
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { continue }
            if UInt32(truncatingIfNeeded: code) == combo.keyCode,
               UInt32(truncatingIfNeeded: modifiers) == combo.carbonModifiers {
                return true
            }
        }
        return false
    }
}
