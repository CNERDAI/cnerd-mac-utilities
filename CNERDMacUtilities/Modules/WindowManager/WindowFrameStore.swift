import ApplicationServices

/// Identifies one window of another app, so its original frame can be remembered.
struct WindowKey: Hashable {
    let element: AXUIElement

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

/// What the Window Manager remembers about a window it has positioned.
struct ManagedWindowState {
    /// Where the window was before the Window Manager first moved it.
    let restoreFrame: CGRect
    /// The frame the window actually ended up with after the last action.
    let appliedFrame: CGRect
    let position: WindowPosition
    let pid: pid_t
}

/// In-memory record of managed windows. Nothing is written to disk.
@MainActor
struct WindowFrameStore {
    private var states: [WindowKey: ManagedWindowState] = [:]
    private static let maximumEntries = 300

    subscript(window: AXUIElement) -> ManagedWindowState? {
        get { states[WindowKey(element: window)] }
        set {
            // Windows that were closed leave entries behind. Clear everything long before it matters.
            if newValue != nil, states.count >= Self.maximumEntries { states.removeAll() }
            states[WindowKey(element: window)] = newValue
        }
    }

    mutating func removeAll(forProcess pid: pid_t) {
        states = states.filter { $0.value.pid != pid }
    }
}
