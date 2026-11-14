import CoreGraphics
import Foundation

/// Finds which display each app's windows are on.
///
/// Uses the public window list (`CGWindowListCopyWindowInfo`). Only the owner and the frame of
/// each window are read, never its title or contents, so no extra permission is needed.
/// Frames are in global display coordinates: origin at the top left of the main display, y grows
/// downward. `CGDisplayBounds` reports displays in the same coordinates.
enum WindowLocator {
    struct Window: Equatable, Sendable {
        let pid: pid_t
        let frame: CGRect
    }

    /// Anything smaller than this on either side is a helper window, not one a person works in.
    static let minimumSide: CGFloat = 40

    /// The normal windows showing right now. Minimized windows, windows of hidden apps, and
    /// windows on another Space are not in the list.
    ///
    /// Off-screen windows are left out on purpose. macOS keeps several invisible windows per app
    /// (one strip per display, and placeholders), so their frames say nothing about where the app is.
    static func onScreenWindows() -> [Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            // Layer 0 is where ordinary app windows live. Menus, the Dock, and this app's taskbars are on other layers.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= minimumSide, frame.height >= minimumSide
            else { return nil }
            return Window(pid: pid, frame: frame)
        }
    }

    /// The displays each process has a window on. A window belongs to the display showing most of it.
    static func displaysByProcess(
        windows: [Window], displays: [(id: UInt32, frame: CGRect)]
    ) -> [pid_t: Set<UInt32>] {
        let frames = displays.map(\.frame)
        var result: [pid_t: Set<UInt32>] = [:]
        for window in windows {
            guard let index = ScreenGeometry.indexOfBestScreen(for: window.frame, among: frames) else { continue }
            result[window.pid, default: []].insert(displays[index].id)
        }
        return result
    }
}
