import AppKit
import ApplicationServices
import Observation

/// Module 001. Windows-style maximize and restore, window snapping, and keyboard shortcuts.
/// Does nothing at all while the module is off or the Accessibility permission is missing.
@MainActor
@Observable
final class WindowManagerController: UtilityModule {
    enum ActionResult: Equatable {
        case success(String)
        case failure(String)

        var text: String {
            switch self {
            case .success(let text), .failure(let text): text
            }
        }

        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    /// Which window an action applies to.
    enum Target {
        /// The frontmost app, whatever it is. Used by keyboard shortcuts.
        case frontmost
        /// The frontmost app, or the last app used before this one when this app is in front.
        /// Used by buttons in the settings window and the menu bar.
        case lastOtherApp
    }

    let sidebarItem = SidebarItem.windowManager

    /// Name of the app the buttons in the settings window will act on.
    private(set) var lastOtherAppName: String?
    private(set) var lastResult: ActionResult?
    /// True while the green button beta is running.
    private(set) var isGreenButtonActive = false
    /// Shortcuts the system refused to register, usually because another app owns them.
    private(set) var unavailableShortcuts: Set<ShortcutAction> = []

    private let settings: AppSettings
    private let permissions: PermissionsService
    private let windows = AccessibilityWindowService()
    private let hotKeys = HotKeyService.shared
    private let greenButton = GreenButtonInterceptor()

    @ObservationIgnored private var frameStore = WindowFrameStore()
    @ObservationIgnored private var lastOtherPID: pid_t?
    @ObservationIgnored private var shortcutsSuspended = false

    /// Extra space to keep free along the edges of a display, for example for the CNERD taskbar.
    @ObservationIgnored var screenInsets: @MainActor (NSScreen) -> ScreenInsets = { _ in .zero }

    init(settings: AppSettings, permissions: PermissionsService) {
        self.settings = settings
        self.permissions = permissions

        greenButton.onGreenButtonClick = { [weak self] window in
            self?.apply(.maximize, to: window, appName: nil)
        }

        NotificationCenter.default.observeOnMain(.appSettingsDidChange) { [weak self] in self?.refresh() }
        NotificationCenter.default.observeOnMain(.accessibilityTrustDidChange) { [weak self] in self?.refresh() }
        observeWorkspace()

        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            noteActivatedApp(pid: front.processIdentifier, name: front.localizedName)
        }
        refresh()
    }

    // MARK: - Status

    var status: ModuleStatus {
        guard settings.windowManagerEnabled else { return .disabled }
        guard permissions.isAccessibilityTrusted else { return .needsAttention("Needs Accessibility permission") }
        return .active("On")
    }

    func isPositionEnabled(_ position: WindowPosition) -> Bool {
        position == .maximize ? settings.maximizeEnabled : settings.snappingEnabled
    }

    func canPerform(_ position: WindowPosition) -> Bool {
        settings.windowManagerEnabled && isPositionEnabled(position) && permissions.isAccessibilityTrusted
    }

    // MARK: - Actions

    /// Moves the target window to a position. Maximize acts as a toggle.
    func perform(_ position: WindowPosition, target: Target) {
        guard settings.windowManagerEnabled, isPositionEnabled(position) else { return }
        guard AXIsProcessTrusted() else {
            permissions.refreshAccessibility()
            lastResult = .failure("Accessibility permission is required to move windows.")
            return
        }
        guard let app = resolveApp(for: target) else {
            lastResult = .failure("Switch to the window you want to move, then try again.")
            return
        }
        guard let window = windows.focusedWindow(ofProcess: app.pid) else {
            lastResult = .failure("\(app.name) has no window that can be moved.")
            return
        }
        apply(position, to: window, appName: app.name)
    }

    /// Pauses the global shortcuts while the user records a new one.
    func setShortcutsSuspended(_ suspended: Bool) {
        guard shortcutsSuspended != suspended else { return }
        shortcutsSuspended = suspended
        refresh()
    }

    // MARK: - Setup

    /// Brings hot keys and the green button tap in line with the current settings and permission.
    func refresh() {
        let isRunning = settings.windowManagerEnabled && permissions.isAccessibilityTrusted

        for action in ShortcutAction.allCases {
            hotKeys.unregister(id: action.hotKeyID)
        }
        var failed: Set<ShortcutAction> = []
        if isRunning, settings.windowShortcutsEnabled, !shortcutsSuspended {
            for action in ShortcutAction.allCases where isPositionEnabled(action.position) {
                guard let combo = settings.shortcuts[action] else { continue }
                let registered = hotKeys.register(id: action.hotKeyID, combo: combo) { [weak self] in
                    self?.perform(action.position, target: .frontmost)
                }
                if !registered { failed.insert(action) }
            }
        }
        if failed != unavailableShortcuts { unavailableShortcuts = failed }

        let wantsGreenButton = isRunning && settings.maximizeEnabled && settings.greenButtonEnabled
        let greenButtonRunning: Bool
        if wantsGreenButton {
            greenButtonRunning = greenButton.start()
        } else {
            greenButton.stop()
            greenButtonRunning = false
        }
        if greenButtonRunning != isGreenButtonActive { isGreenButtonActive = greenButtonRunning }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        _ = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            let name = app.localizedName
            MainActor.assumeIsolated { self?.noteActivatedApp(pid: pid, name: name) }
        }

        _ = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.noteTerminatedApp(pid: pid) }
        }
    }

    private func noteActivatedApp(pid: pid_t, name: String?) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lastOtherPID = pid
        lastOtherAppName = name ?? "the last app"
    }

    private func noteTerminatedApp(pid: pid_t) {
        frameStore.removeAll(forProcess: pid)
        if lastOtherPID == pid {
            lastOtherPID = nil
            lastOtherAppName = nil
        }
    }

    // MARK: - Window logic

    private func resolveApp(for target: Target) -> (pid: pid_t, name: String)? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication,
           target == .frontmost || front.processIdentifier != ownPID {
            return (front.processIdentifier, front.localizedName ?? "The app")
        }
        if let pid = lastOtherPID, let name = lastOtherAppName {
            return (pid, name)
        }
        return nil
    }

    private func apply(_ position: WindowPosition, to window: AXUIElement, appName: String?) {
        // Green button clicks arrive without an app name, so look it up from the window's process.
        let name = appName
            ?? windows.processID(of: window).flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? "the window"

        guard !windows.isFullScreen(window) else {
            lastResult = .failure("That window is in Full Screen. Leave Full Screen first.")
            return
        }
        guard let currentFrame = windows.frame(of: window) else {
            lastResult = .failure("Could not read the window's size. The app may not support it.")
            return
        }
        let screens = screensInAccessibilityCoordinates()
        guard let screenIndex = ScreenGeometry.indexOfBestScreen(for: currentFrame, among: screens.map(\.frame)) else {
            lastResult = .failure("No display found for that window.")
            return
        }

        let saved = frameStore[window]
        // "Managed" means the window is still where the Window Manager last put it.
        // If the user has moved or resized it since, the saved frame is out of date.
        let isManaged = saved.map { ScreenGeometry.isApproximatelyEqual(currentFrame, $0.appliedFrame) } ?? false

        // Maximize on a window that is already maximized restores it.
        if position == .maximize, isManaged, let saved, saved.position == .maximize {
            windows.setFrame(saved.restoreFrame, of: window)
            frameStore[window] = nil
            lastResult = .success("Restored \(name).")
            return
        }

        let targetFrame = ScreenGeometry.targetFrame(
            for: position,
            in: screens[screenIndex].visibleFrame,
            currentSize: currentFrame.size
        )
        guard windows.setFrame(targetFrame, of: window) else {
            lastResult = .failure("\(name.capitalizedFirst) did not allow its window to be moved.")
            return
        }

        let restoreFrame = (isManaged ? saved?.restoreFrame : nil) ?? currentFrame
        frameStore[window] = ManagedWindowState(
            restoreFrame: restoreFrame,
            appliedFrame: windows.frame(of: window) ?? targetFrame,
            position: position,
            pid: windows.processID(of: window) ?? 0
        )
        switch position {
        case .maximize: lastResult = .success("Maximized \(name).")
        case .leftHalf: lastResult = .success("Moved \(name) to the left half.")
        case .rightHalf: lastResult = .success("Moved \(name) to the right half.")
        case .center: lastResult = .success("Centered \(name).")
        }
    }

    /// Every display's full frame and usable frame, converted to Accessibility coordinates.
    private func screensInAccessibilityCoordinates() -> [(frame: CGRect, visibleFrame: CGRect)] {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        // A hidden Dock frees its strip of the screen for windows.
        let dockIsHidden = DockInfo.isAutoHidden
        return screens.map { screen in
            let usable = screenInsets(screen).applied(toAppKitRect: screen.usableFrame(dockIsHidden: dockIsHidden))
            return (
                frame: ScreenGeometry.accessibilityRect(fromAppKit: screen.frame, primaryScreenHeight: primaryHeight),
                visibleFrame: ScreenGeometry.accessibilityRect(fromAppKit: usable, primaryScreenHeight: primaryHeight)
            )
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
