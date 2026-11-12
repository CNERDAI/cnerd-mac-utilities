import AppKit
import ApplicationServices

/// Thin wrapper around the public Accessibility API (AXUIElement) for reading and moving
/// windows that belong to other apps. Requires the Accessibility permission.
/// All frames are in Accessibility coordinates (top-left origin).
@MainActor
struct AccessibilityWindowService {
    /// How long to wait for another app to answer. Keeps a frozen app from freezing this one.
    private static let messagingTimeout: Float = 1.0

    private let systemWide: AXUIElement

    init() {
        systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    // MARK: - Finding windows

    /// The focused window of an app, or its main window if nothing is focused.
    func focusedWindow(ofProcess pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        return elementAttribute(app, kAXFocusedWindowAttribute) ?? elementAttribute(app, kAXMainWindowAttribute)
    }

    /// The UI element under a screen point, in any app.
    func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        return result == .success ? element : nil
    }

    /// The window that contains an element.
    func window(containing element: AXUIElement) -> AXUIElement? {
        elementAttribute(element, kAXWindowAttribute)
    }

    func subrole(of element: AXUIElement) -> String? {
        copyAttribute(element, kAXSubroleAttribute) as? String
    }

    func processID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    // MARK: - Reading and changing frames

    func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(element, kAXPositionAttribute),
              let sizeValue = axValue(element, kAXSizeAttribute)
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Moves and resizes a window. Returns false if the app refused.
    @discardableResult
    func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        var origin = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        // Size, move, then size again. The first resize lets the window fit on the destination
        // display, and the second corrects apps that clamp the size during the move.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return moved == .success && resized == .success
    }

    /// True when the window is in macOS Full Screen mode.
    func isFullScreen(_ window: AXUIElement) -> Bool {
        (copyAttribute(window, "AXFullScreen") as? Bool) ?? false
    }

    // MARK: - Attribute helpers

    private func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = copyAttribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        guard let value = copyAttribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
