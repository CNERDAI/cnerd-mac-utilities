import AppKit

/// Read-only facts about the macOS Dock, taken from the Dock's own preferences.
/// Reading them needs no permission.
@MainActor
enum DockInfo {
    /// True when the Dock is set to hide automatically (or has been turned off from this app).
    static var isAutoHidden: Bool {
        let dockID = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dockID)
        return CFPreferencesGetAppBooleanValue("autohide" as CFString, dockID, nil)
    }
}

extension NSScreen {
    /// The area that is free for windows on this display.
    ///
    /// Normally this is `visibleFrame`: the display minus the menu bar and the Dock. On macOS 27,
    /// `visibleFrame` was measured to keep the Dock's strip reserved even while the Dock is hidden.
    /// So when the Dock is hidden, only the menu bar is subtracted and the Dock's strip counts as free.
    func usableFrame(dockIsHidden: Bool) -> NSRect {
        guard dockIsHidden else { return visibleFrame }
        let menuBarHeight = max(frame.maxY - visibleFrame.maxY, 0)
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBarHeight)
    }
}
