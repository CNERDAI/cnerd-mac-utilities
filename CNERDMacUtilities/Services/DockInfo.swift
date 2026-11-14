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

    /// The apps kept in the macOS Dock, in the Dock's order. Finder and the Trash are not in
    /// this list, because the Dock always shows them.
    static var keptApps: [DockApp] {
        let dockID = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dockID)
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, dockID) as? [[String: Any]] else { return [] }
        return DockApp.apps(fromDockTiles: tiles)
    }
}

/// One app kept in the macOS Dock.
struct DockApp: Identifiable, Equatable, Sendable {
    let bundleID: String
    /// The name the Dock shows for it.
    let name: String

    var id: String { bundleID }

    /// Reads the Dock's "persistent-apps" preference. Each entry is a tile with the app's bundle
    /// identifier and label under "tile-data". Spacers and anything else without a bundle
    /// identifier are skipped, and an app listed twice is kept once. These keys are the Dock's
    /// own and are not documented by Apple, so anything unexpected is simply left out.
    static func apps(fromDockTiles tiles: [[String: Any]]) -> [DockApp] {
        var seen = Set<String>()
        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let bundleID = data["bundle-identifier"] as? String, !bundleID.isEmpty,
                  seen.insert(bundleID).inserted
            else { return nil }
            let label = (data["file-label"] as? String) ?? ""
            return DockApp(bundleID: bundleID, name: label.isEmpty ? bundleID : label)
        }
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
