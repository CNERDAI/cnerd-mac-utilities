import AppKit
import Observation

/// Module 004. A Windows-style taskbar drawn by this app on the chosen displays,
/// plus switches for the real macOS Dock.
///
/// The taskbar is an ordinary floating panel. macOS does not let apps reserve screen space
/// the way the Dock does, so only this app's Window Manager knows to stay clear of it.
/// See docs/FEASIBILITY.md.
@MainActor
@Observable
final class TaskbarController: UtilityModule {
    let sidebarItem = SidebarItem.taskbar
    let settings: AppSettings

    /// Apps on the taskbar, in the order the user arranged them.
    private(set) var apps: [TaskbarApp] = []
    /// How many displays currently show a taskbar.
    private(set) var visibleBarCount = 0

    // Mirror of the macOS Dock's own settings.
    private(set) var dockAutoHide = false
    private(set) var dockPosition: DockPosition = .bottom
    /// 0 is the smallest Dock, 1 the largest.
    private(set) var dockSize: Double = 0.3
    /// True when the Dock has been turned off from this app.
    private(set) var isDockTurnedOff = false
    private(set) var dockMessage: String?

    /// The app being dragged to a new spot on the taskbar.
    @ObservationIgnored var draggedAppID: String?

    @ObservationIgnored private var panels: [UInt32: TaskbarPanel] = [:]
    @ObservationIgnored private var dockFollowUp: Task<Void, Never>?
    /// Name, icon, and location of kept apps that are not running.
    @ObservationIgnored private var installedAppCache: [String: (url: URL, name: String, icon: NSImage)] = [:]

    private static let dockBundleID = "com.apple.dock"
    /// With this delay the hidden Dock never slides back in when the pointer touches its edge.
    private static let dockOffDelay: Double = 1000

    init(settings: AppSettings) {
        self.settings = settings
        refreshDockState()

        NotificationCenter.default.observeOnMain(.appSettingsDidChange) { [weak self] in self?.refresh() }
        NotificationCenter.default.observeOnMain(NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.refresh() }

        // Event driven: the list only changes when an app starts, quits, hides, or comes to the front.
        let workspaceEvents: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in workspaceEvents {
            NSWorkspace.shared.notificationCenter.observeOnMain(name) { [weak self] in self?.refresh() }
        }

        // The Dock announces setting changes made anywhere (System Settings, Terminal, this app).
        // This notification name is not documented by Apple. If it ever stops arriving, the taskbar
        // still re-seats on the next app or display change.
        DistributedNotificationCenter.default().observeOnMain(Notification.Name("com.apple.dock.prefchanged")) { [weak self] in
            self?.followDockChange(afterMilliseconds: [400, 900, 1500])
        }

        // The controller is created while SwiftUI is still setting up the app. Showing a window
        // that hosts SwiftUI content at that moment is not allowed, so the first refresh waits a turn.
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    var status: ModuleStatus {
        guard settings.taskbarEnabled else { return .disabled }
        return .active(visibleBarCount == 1 ? "On, 1 display" : "On, \(visibleBarCount) displays")
    }

    /// How thick the bar is: its height on the top or bottom edge, its width on the left or right edge.
    var thickness: CGFloat {
        TaskbarLayout.thickness(
            position: settings.taskbarPosition,
            iconSize: settings.taskbarIconSize.points,
            showNames: settings.taskbarShowAppNames,
            namePosition: settings.taskbarNamePosition,
            nameSize: settings.taskbarNameSize.points
        )
    }

    private var isFloating: Bool { settings.taskbarCornerStyle == .rounded }

    // MARK: - Taskbar panels

    /// Creates, moves, or removes taskbars so they match the settings and the connected displays.
    func refresh() {
        guard settings.taskbarEnabled else {
            removePanels(keeping: [])
            reloadApps()
            return
        }

        // A hidden Dock frees its strip of the screen, and the taskbar slides into it.
        let dockIsHidden = DockInfo.isAutoHidden
        var wanted: [UInt32: NSScreen] = [:]
        for (index, screen) in NSScreen.screens.enumerated() where settings.taskbarDisplayMode.includes(screenIndex: index) {
            wanted[Self.displayID(of: screen) ?? UInt32(index)] = screen
        }
        removePanels(keeping: Set(wanted.keys))

        for (id, screen) in wanted {
            // Placed inside the usable area, so it never covers the menu bar or a visible Dock.
            // When the Dock hides or moves, the usable area changes and the taskbar follows.
            let frame = TaskbarLayout.frame(
                in: screen.usableFrame(dockIsHidden: dockIsHidden),
                position: settings.taskbarPosition,
                thickness: thickness,
                floating: isFloating
            )
            if let panel = panels[id] {
                if panel.frame != frame {
                    // Slide to the new spot instead of jumping.
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        panel.animator().setFrame(frame, display: true)
                    }
                }
                if !panel.isVisible { panel.orderFrontRegardless() }
            } else {
                let panel = TaskbarPanel(rootView: TaskbarView(controller: self))
                panel.setFrame(frame, display: true)
                panel.orderFrontRegardless()
                panels[id] = panel
            }
        }
        if visibleBarCount != panels.count { visibleBarCount = panels.count }
        reloadApps()
    }

    /// Space Window Manager should leave free on a display for the taskbar.
    func reservedInsets(for screen: NSScreen) -> ScreenInsets {
        guard settings.taskbarEnabled, settings.taskbarReserveSpace,
              let id = Self.displayID(of: screen), panels[id] != nil
        else { return .zero }
        return TaskbarLayout.insets(position: settings.taskbarPosition, thickness: thickness, floating: isFloating)
    }

    private func removePanels(keeping ids: Set<UInt32>) {
        for id in Array(panels.keys) where !ids.contains(id) {
            panels[id]?.orderOut(nil)
            panels[id] = nil
        }
        if visibleBarCount != panels.count { visibleBarCount = panels.count }
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: - App list

    private func reloadApps() {
        guard !panels.isEmpty else {
            if !apps.isEmpty { apps = [] }
            return
        }
        let workspace = NSWorkspace.shared
        let frontPID = workspace.frontmostApplication?.processIdentifier

        var runningByID: [String: NSRunningApplication] = [:]
        var launchOrder: [String] = []
        for app in workspace.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            let id = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            if runningByID[id] == nil {
                runningByID[id] = app
                launchOrder.append(id)
            }
        }

        // Remember a spot for every app, so it comes back to the same place next time.
        let pinned = settings.taskbarPinnedApps
        let order = TaskbarOrdering.merged(order: settings.taskbarAppOrder, adding: pinned + launchOrder)
        if order != settings.taskbarAppOrder { settings.taskbarAppOrder = order }

        let pinnedSet = Set(pinned)
        let current = TaskbarOrdering.visible(order: order, pinned: pinnedSet, running: launchOrder).compactMap { id -> TaskbarApp? in
            if let running = runningByID[id] {
                return TaskbarApp(
                    id: id,
                    pid: running.processIdentifier,
                    name: running.localizedName ?? "App",
                    bundleURL: running.bundleURL,
                    icon: running.icon,
                    isActive: running.processIdentifier == frontPID,
                    isHidden: running.isHidden,
                    isPinned: pinnedSet.contains(id)
                )
            }
            // Kept on the taskbar but not running. Skipped if the app is no longer installed.
            guard let installed = installedApp(for: id) else { return nil }
            return TaskbarApp(
                id: id, pid: nil, name: installed.name, bundleURL: installed.url, icon: installed.icon,
                isActive: false, isHidden: false, isPinned: true
            )
        }
        if current != apps { apps = current }
    }

    private func installedApp(for bundleID: String) -> (url: URL, name: String, icon: NSImage)? {
        if let cached = installedAppCache[bundleID], FileManager.default.fileExists(atPath: cached.url.path) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            installedAppCache[bundleID] = nil
            return nil
        }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        let info = (url: url, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        installedAppCache[bundleID] = info
        return info
    }

    // MARK: - Taskbar actions

    /// Opens an app that is not running, or brings a running app to the front. Clicking the app
    /// that is already in front hides it, like clicking the active app on the Windows taskbar.
    func activate(_ app: TaskbarApp) {
        guard let pid = app.pid, let running = NSRunningApplication(processIdentifier: pid) else {
            open(app)
            return
        }
        if running.isActive {
            running.hide()
            return
        }
        if running.isHidden { running.unhide() }
        if app.bundleURL != nil {
            open(app)
        } else {
            _ = running.activate(options: [])
        }
    }

    /// Same as clicking the app in the Dock: it launches or comes forward, and reopens a window if it has none.
    private func open(_ app: TaskbarApp) {
        guard let url = app.bundleURL else {
            reloadApps()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    func hide(_ app: TaskbarApp) {
        guard let pid = app.pid else { return }
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    /// Asks the app to quit normally. The app can still ask to save changes.
    func quit(_ app: TaskbarApp) {
        guard let pid = app.pid else { return }
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    /// Keep in Taskbar, or Remove from Taskbar.
    func setPinned(_ pinned: Bool, app: TaskbarApp) {
        guard app.canBePinned else { return }
        var list = settings.taskbarPinnedApps
        if pinned {
            if !list.contains(app.id) { list.append(app.id) }
        } else {
            list.removeAll { $0 == app.id }
        }
        settings.taskbarPinnedApps = list
    }

    func showInFinder(_ app: TaskbarApp) {
        guard let url = app.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Brings every window of the app forward, then asks Mission Control for its
    /// "application windows" view, the one the Dock's Show All Windows uses.
    func showAllWindows(of app: TaskbarApp) {
        guard let pid = app.pid, let running = NSRunningApplication(processIdentifier: pid) else { return }
        if running.isHidden { running.unhide() }
        _ = running.activate(options: [.activateAllWindows])

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            Self.showApplicationWindowsOverview()
        }
    }

    /// Mission Control accepts "2" to show the front app's windows. Apple does not document this
    /// argument. If the tool is missing, the windows were still brought forward above.
    private static func showApplicationWindowsOverview() {
        let tool = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["2"]
        try? process.run()
    }

    /// Puts the dragged app before or after the app the pointer is over, and saves the new order.
    /// Returns true if the order changed.
    @discardableResult
    func placeDraggedApp(before: Bool, targetID: String) -> Bool {
        guard let dragged = draggedAppID else { return false }
        let order = TaskbarOrdering.placing(dragged, before: before, target: targetID, in: settings.taskbarAppOrder)
        guard order != settings.taskbarAppOrder else { return false }
        settings.taskbarAppOrder = order
        return true
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    /// Opens the Trash in Finder.
    func openTrash() {
        guard let url = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - macOS Dock

    /// Converts the Dock's stored icon size (16 to 128 pixels) to the 0 to 1 scale System Events uses.
    static func dockSize(fromTileSize tileSize: Double) -> Double {
        min(max((tileSize - 16) / 112, 0), 1)
    }

    /// Reads the Dock's current settings without asking for any permission.
    func refreshDockState() {
        let dockID = Self.dockBundleID as CFString
        CFPreferencesAppSynchronize(dockID)
        let autoHide = CFPreferencesGetAppBooleanValue("autohide" as CFString, dockID, nil)
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, dockID) as? String
        let position = DockPosition(rawValue: orientation ?? "") ?? .bottom
        let delay = (CFPreferencesCopyAppValue("autohide-delay" as CFString, dockID) as? NSNumber)?.doubleValue ?? 0
        let turnedOff = autoHide && delay >= 100

        // Only assign real changes, so views do not redraw for nothing.
        if autoHide != dockAutoHide { dockAutoHide = autoHide }
        if position != dockPosition { dockPosition = position }
        if turnedOff != isDockTurnedOff { isDockTurnedOff = turnedOff }
        if let tileSize = CFPreferencesCopyAppValue("tilesize" as CFString, dockID) as? NSNumber {
            let size = Self.dockSize(fromTileSize: tileSize.doubleValue)
            if size != dockSize { dockSize = size }
        }
    }

    func setDockAutoHide(_ enabled: Bool) {
        guard !isDockTurnedOff else { return }
        if runDockCommand("set autohide to \(enabled)") { dockAutoHide = enabled }
    }

    func setDockPosition(_ position: DockPosition) {
        if runDockCommand("set screen edge to \(position.rawValue)") { dockPosition = position }
    }

    func setDockSize(_ size: Double) {
        let clamped = min(max(size, 0), 1)
        if runDockCommand("set dock size to \(String(format: "%.3f", clamped))") { dockSize = clamped }
    }

    /// Turns the Dock off, or brings it back.
    ///
    /// macOS has no supported way to remove the Dock. This hides it and sets the Dock's own
    /// "autohide-delay" value so high that it never slides back in. That value is not documented
    /// by Apple, and the Dock has to restart to read it. Turning this off removes the value again
    /// and puts auto-hide back the way it was. See docs/FEASIBILITY.md.
    func setDockTurnedOff(_ off: Bool) {
        let dockID = Self.dockBundleID as CFString
        if off {
            settings.dockAutoHideBeforeOff = dockAutoHide
            CFPreferencesSetAppValue("autohide" as CFString, true as CFBoolean, dockID)
            CFPreferencesSetAppValue("autohide-delay" as CFString, Self.dockOffDelay as CFNumber, dockID)
        } else {
            CFPreferencesSetAppValue("autohide-delay" as CFString, nil, dockID)
            CFPreferencesSetAppValue("autohide" as CFString, settings.dockAutoHideBeforeOff as CFBoolean, dockID)
        }
        guard CFPreferencesAppSynchronize(dockID) else {
            dockMessage = "The Dock setting could not be saved."
            refreshDockState()
            return
        }

        // The Dock only reads this value when it starts. macOS relaunches it right away.
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["Dock"]
        do {
            try restart.run()
            dockMessage = nil
        } catch {
            dockMessage = "The Dock could not be restarted. The change applies the next time you log in."
        }
        refreshDockState()
        followDockChange(afterMilliseconds: [1000, 1500, 2000])
    }

    /// Changes a Dock setting through System Events, Apple's scripting interface for system preferences.
    /// The first use shows the macOS prompt asking to let this app control System Events.
    private func runDockCommand(_ command: String) -> Bool {
        let source = """
        with timeout of 5 seconds
            tell application "System Events" to tell dock preferences to \(command)
        end timeout
        """
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                dockMessage = "macOS is blocking access to System Events. Allow it in System Settings, Privacy & Security, Automation."
            } else {
                let detail = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                dockMessage = "The Dock setting could not be changed: \(detail)"
            }
            return false
        }
        dockMessage = nil
        followDockChange(afterMilliseconds: [400, 800, 1300])
        return true
    }

    /// The Dock takes a moment to hide, show, or move. Re-read its settings and slide the
    /// taskbars into place a few times over the next seconds, then stop.
    private func followDockChange(afterMilliseconds steps: [Int]) {
        dockFollowUp?.cancel()
        dockFollowUp = Task { @MainActor [weak self] in
            for step in steps {
                try? await Task.sleep(for: .milliseconds(step))
                if Task.isCancelled { return }
                self?.refreshDockState()
                self?.refresh()
            }
        }
    }
}
