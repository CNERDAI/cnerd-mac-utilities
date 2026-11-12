import AppKit
import ApplicationServices

/// Beta. Turns a click on a window's green button into a Windows-style maximize.
///
/// How it works, using public APIs only:
/// 1. A CGEventTap sees left mouse clicks before they reach apps (needs the Accessibility permission).
/// 2. On mouse down, the Accessibility API is asked what is under the pointer.
/// 3. If it is a standard zoom / full screen button, the click is held back and the window is
///    maximized or restored instead. Every other click passes through untouched.
///
/// The tap fails safe: when anything is uncertain, the click goes to macOS unchanged.
/// Limits are listed in docs/FEASIBILITY.md.
@MainActor
final class GreenButtonInterceptor {
    /// Called with the window whose green button was clicked.
    var onGreenButtonClick: ((AXUIElement) -> Void)?

    /// The interceptor the C callback forwards to. Only one tap exists at a time.
    fileprivate static weak var active: GreenButtonInterceptor?

    /// Traffic light buttons always sit inside this many points from the top of a window.
    private static let titleBarStripHeight: CGFloat = 64

    private struct PendingClick {
        let window: AXUIElement
        let buttonFrame: CGRect
    }

    private let windows = AccessibilityWindowService()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingClick: PendingClick?

    var isRunning: Bool { tap != nil }

    /// Starts watching clicks. Returns false if macOS refuses, usually because the
    /// Accessibility permission is missing.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: greenButtonTapCallback,
            userInfo: nil
        ) else { return false }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        Self.active = self
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        pendingClick = nil
        if Self.active === self { Self.active = nil }
    }

    /// Decides what to do with one mouse event. Returns true to hold the event back.
    fileprivate func handle(type: CGEventType, location: CGPoint, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches a tap off if it is ever slow. Turn it back on.
            pendingClick = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false

        case .leftMouseDown:
            pendingClick = nil
            // Modifier clicks keep their macOS meaning (Option-click still zooms).
            guard flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift]).isEmpty else { return false }
            // Cheap check first, so most clicks never trigger an Accessibility query.
            guard isNearTopOfAWindow(location) else { return false }
            guard let click = greenButtonClick(at: location) else { return false }
            pendingClick = click
            return true

        case .leftMouseUp:
            guard let click = pendingClick else { return false }
            pendingClick = nil
            // Like a normal button: only act if the pointer is still on the button when released.
            if click.buttonFrame.insetBy(dx: -3, dy: -3).contains(location) {
                onGreenButtonClick?(click.window)
            }
            return true

        default:
            return false
        }
    }

    /// True when the point is in the top strip of the frontmost normal window under it.
    /// Uses the window list, which does not talk to other apps.
    private func isNearTopOfAWindow(_ point: CGPoint) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }

        for info in list {
            // Layer 0 holds normal app windows. Menus, the Dock, and overlays use other layers.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.contains(point)
            else { continue }
            return point.y - bounds.minY <= Self.titleBarStripHeight
        }
        return false
    }

    /// Returns the window and button frame if the point is on a standard green button
    /// of a window that is not in Full Screen.
    private func greenButtonClick(at point: CGPoint) -> PendingClick? {
        guard let element = windows.element(at: point),
              let subrole = windows.subrole(of: element),
              subrole == kAXFullScreenButtonSubrole || subrole == kAXZoomButtonSubrole,
              let window = windows.window(containing: element),
              !windows.isFullScreen(window),
              let buttonFrame = windows.frame(of: element)
        else { return nil }
        return PendingClick(window: window, buttonFrame: buttonFrame)
    }
}

/// C callback for the event tap. The tap's run loop source is on the main run loop,
/// so this always runs on the main thread.
private func greenButtonTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let location = event.location
    let flags = event.flags
    let holdBack = MainActor.assumeIsolated {
        GreenButtonInterceptor.active?.handle(type: type, location: location, flags: flags) ?? false
    }
    return holdBack ? nil : Unmanaged.passUnretained(event)
}
