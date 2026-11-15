import AppKit
import Observation
import UniformTypeIdentifiers

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
    /// The displays that show a taskbar, the main taskbar first.
    private(set) var barDisplays: [UInt32] = []
    /// How long each display's taskbar is, along its edge of the screen.
    private(set) var barLengths: [UInt32: CGFloat] = [:]
    /// The displays that show a taskbar, the main taskbar first, as App Icon Controls lists them.
    private(set) var displays: [TaskbarDisplay] = []
    /// Chosen apps that are running but are not in `apps`, because they run as menu bar apps
    /// without a Dock icon (Elgato Camera Hub is one). See `chosenApps(on:)`.
    private(set) var chosenBackgroundApps: [String: TaskbarApp] = [:]
    /// The displays each app has a window on, or had one on when it last showed a window.
    /// Only filled while apps are shown per display. See `refreshWindowLocations`.
    private(set) var appDisplays: [String: Set<UInt32>] = [:]

    // Mirror of the macOS Dock's own settings.
    private(set) var dockAutoHide = false
    private(set) var dockPosition: DockPosition = .bottom
    /// 0 is the smallest Dock, 1 the largest.
    private(set) var dockSize: Double = 0.3
    /// True when the Dock has been turned off from this app.
    private(set) var isDockTurnedOff = false
    private(set) var dockMessage: String?

    /// Disks the Trash menu can eject: external drives, disk images, and network volumes.
    private(set) var ejectableVolumes: [EjectableVolume] = []
    /// Whether the Trash has anything in it, so the taskbar can show a full or an empty Trash.
    let trash = TrashMonitor()

    /// The app being dragged to a new spot, on the taskbar or in App Icon Controls.
    @ObservationIgnored private(set) var draggedAppID: String?
    /// The group being dragged to a new spot in App Icon Controls.
    @ObservationIgnored private(set) var draggedGroupID: String?
    /// Opens the main window on one settings screen. Set by `AppEnvironment`.
    @ObservationIgnored var showSettings: ((SidebarItem) -> Void)?

    /// The pop-up that is open, if any: Hidden Apps, or the More pop-up of one taskbar.
    private(set) var shownPopup: TaskbarPopup?
    @ObservationIgnored private var popupPanel: TaskbarPanel?
    /// The button the pop-up belongs to, in screen coordinates.
    @ObservationIgnored private var popupAnchor: NSRect?
    /// Watch for clicks outside the pop-up. Only installed while it is open.
    @ObservationIgnored private var outsideClickMonitors: [Any] = []

    /// Watch for the end of a drag, which is when a window can land on another display.
    /// Only installed while apps are shown per display.
    @ObservationIgnored private var windowMoveMonitors: [Any] = []
    @ObservationIgnored private var windowCheck: Task<Void, Never>?
    @ObservationIgnored private var windowFollowUp: Task<Void, Never>?
    /// Drawn width of app names, so each name is only measured once per text size.
    @ObservationIgnored private var nameWidthCache: [String: CGFloat] = [:]

    @ObservationIgnored private var panels: [UInt32: TaskbarPanel] = [:]
    /// A drag of a taskbar toward another edge of the screen, while it is under way.
    @ObservationIgnored private var barDrag: BarDrag?
    /// The outline that shows where the dragged taskbar will land.
    @ObservationIgnored private var barDragPreview: TaskbarDragPreview?
    @ObservationIgnored private var dockFollowUp: Task<Void, Never>?
    /// Name, icon, and location of kept apps that are not running.
    @ObservationIgnored private var installedAppCache: [String: (url: URL, name: String, icon: NSImage)] = [:]
    /// The topic worked out for each app, so its Info.plist is only read once.
    @ObservationIgnored private var topicCache: [String: AppTopic] = [:]
    /// This app's own icon, drawn from the logo artwork. See `makeOwnIcon`.
    @ObservationIgnored private let ownIcon: NSImage? = TaskbarController.makeOwnIcon()

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
            NSWorkspace.shared.notificationCenter.observeOnMain(name) { [weak self] in
                self?.refresh()
                // An app's windows show up a moment after the app itself is announced.
                self?.followWindowChanges()
                // Most things land in the Trash from Finder, so look again when apps come and go.
                self?.trash.refresh()
            }
        }
        // An open pop-up closes as soon as another app comes to the front.
        NSWorkspace.shared.notificationCenter.observeOnMain(NSWorkspace.didActivateApplicationNotification) { [weak self] in
            self?.closePopup()
        }
        // This app's own windows report when they land on another display.
        NotificationCenter.default.observeOnMain(NSWindow.didChangeScreenNotification) { [weak self] in
            self?.scheduleWindowCheck()
        }

        // The Trash menu lists disks that can be ejected. The list only changes when a disk comes or goes.
        let volumeEvents: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        for name in volumeEvents {
            NSWorkspace.shared.notificationCenter.observeOnMain(name) { [weak self] in self?.refreshVolumes() }
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
            self?.refreshVolumes()
            self?.turnDockOffAgainAfterLaunch()
        }
    }

    var status: ModuleStatus {
        guard settings.taskbarEnabled else { return .disabled }
        return .active(visibleBarCount == 1 ? "On, 1 display" : "On, \(visibleBarCount) displays")
    }

    /// How thick the bar is: its height on the top or bottom edge, its width on the left or right edge.
    var thickness: CGFloat { thickness(at: settings.taskbarPosition) }

    /// How thick the bar would be on a given edge. A side bar with names beside the icons is wider.
    func thickness(at position: TaskbarPosition) -> CGFloat {
        TaskbarLayout.thickness(
            position: position,
            iconSize: CGFloat(settings.taskbarIconPoints),
            showNames: settings.taskbarShowAppNames,
            namePosition: settings.taskbarNamePosition,
            nameSize: settings.taskbarNameSize.points
        )
    }

    private var isFloating: Bool { settings.taskbarCornerStyle == .rounded }

    // MARK: - Taskbar panels

    /// Creates, moves, or removes taskbars so they match the settings and the connected displays.
    func refresh() {
        // The Trash is only watched while a taskbar shows it.
        trash.isWatching = settings.taskbarEnabled && settings.taskbarShowTrash
        guard settings.taskbarEnabled else {
            closePopup()
            endBarDrag()
            removePanels(keeping: [])
            if !barDisplays.isEmpty { barDisplays = [] }
            if !barLengths.isEmpty { barLengths = [:] }
            if !displays.isEmpty { displays = [] }
            updateWindowTracking()
            reloadApps()
            return
        }

        // A hidden Dock frees its strip of the screen, and the taskbar slides into it.
        let dockIsHidden = DockInfo.isAutoHidden
        // In screen order. The first screen is the main display, so its taskbar comes first.
        var wanted: [(id: UInt32, screen: NSScreen)] = []
        for (index, screen) in NSScreen.screens.enumerated() where settings.taskbarDisplayMode.includes(screenIndex: index) {
            let id = Self.displayID(of: screen) ?? UInt32(index)
            if !wanted.contains(where: { $0.id == id }) { wanted.append((id, screen)) }
        }
        removePanels(keeping: Set(wanted.map(\.id)))

        var lengths: [UInt32: CGFloat] = [:]
        for (id, screen) in wanted {
            // Placed inside the usable area, so it never covers the menu bar or a visible Dock.
            // When the Dock hides or moves, the usable area changes and the taskbar follows.
            let frame = TaskbarLayout.frame(
                in: screen.usableFrame(dockIsHidden: dockIsHidden),
                position: settings.taskbarPosition,
                thickness: thickness,
                floating: isFloating
            )
            lengths[id] = settings.taskbarPosition.isHorizontal ? frame.width : frame.height
            if let panel = panels[id] {
                if panel.frame != frame {
                    let current = panel.frame
                    let sameThickness = settings.taskbarPosition.isHorizontal
                        ? current.height == frame.height
                        : current.width == frame.width
                    if sameThickness {
                        // Slide to the new spot instead of jumping.
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.25
                            panel.animator().setFrame(frame, display: true)
                        }
                    } else {
                        // The bar itself changed size, for example while the icon size slider is dragged.
                        // Follow right away so the bar keeps up with the pointer.
                        panel.setFrame(frame, display: true)
                    }
                }
                if !panel.isVisible { panel.orderFrontRegardless() }
            } else {
                let panel = TaskbarPanel(rootView: TaskbarView(controller: self, displayID: id))
                panel.onBarDrag = { [weak self, weak panel] phase in
                    guard let panel else { return }
                    self?.handleBarDrag(phase, from: panel)
                }
                panel.setFrame(frame, display: true)
                panel.orderFrontRegardless()
                panels[id] = panel
            }
        }
        if visibleBarCount != panels.count { visibleBarCount = panels.count }
        let displays = wanted.map(\.id)
        if displays != barDisplays { barDisplays = displays }
        if lengths != barLengths { barLengths = lengths }
        let mainScreen = NSScreen.screens.first
        let shown = wanted.map { item in
            TaskbarDisplay(
                id: item.id, key: Self.displayKey(of: item.id), name: item.screen.localizedName,
                size: item.screen.frame.size, isMain: item.screen == mainScreen
            )
        }
        if shown != self.displays { self.displays = shown }
        updateWindowTracking()
        reloadApps()
        updatePopupPanel()
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
            panels[id]?.cancelBarDrag()
            panels[id]?.orderOut(nil)
            panels[id] = nil
        }
        if visibleBarCount != panels.count { visibleBarCount = panels.count }
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The display's UUID as text. Unlike the display number, it stays the same after a restart
    /// and after the display is unplugged and plugged back in, so saved rules find their display.
    private static func displayKey(of id: UInt32) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String?
        else { return "display:\(id)" }
        return text
    }

    // MARK: - Moving the bar to another edge

    private struct BarDrag {
        /// The edge the bar lands on if the button is let go now.
        var target: TaskbarPosition
        /// The display the dragged bar is on, and the part of it that is free for the bar.
        let screen: NSRect
        let usable: NSRect
        /// Where the dragged bar is now. A drag that stays on it does not move it.
        let bar: NSRect
    }

    /// Moves every taskbar to an edge of its display.
    func setPosition(_ position: TaskbarPosition) {
        if settings.taskbarPosition != position { settings.taskbarPosition = position }
    }

    /// Follows a drag of the empty part of a taskbar. While the pointer moves, an outline shows
    /// the edge the taskbar would land on. Letting go moves the taskbar there. The position is
    /// one setting for all displays, so every taskbar moves with it.
    private func handleBarDrag(_ phase: TaskbarPanel.BarDragPhase, from panel: TaskbarPanel) {
        switch phase {
        case .moved(let point):
            guard settings.taskbarEnabled else { return }
            if barDrag == nil {
                guard let screen = panel.screen ?? NSScreen.main else { return }
                closePopup()
                // Read once per drag. The Dock does not change while the button is held down.
                barDrag = BarDrag(
                    target: settings.taskbarPosition,
                    screen: screen.frame,
                    usable: screen.usableFrame(dockIsHidden: DockInfo.isAutoHidden),
                    bar: panel.frame
                )
            }
            guard var drag = barDrag else { return }
            drag.target = TaskbarLayout.dragTarget(
                for: point, bar: drag.bar, home: settings.taskbarPosition, screen: drag.screen, current: drag.target
            )
            barDrag = drag
            let frame = TaskbarLayout.frame(
                in: drag.usable, position: drag.target, thickness: thickness(at: drag.target), floating: isFloating
            )
            if barDragPreview == nil { barDragPreview = TaskbarDragPreview() }
            barDragPreview?.show(frame: frame, cornerRadius: isFloating ? TaskbarLayout.roundedCornerRadius : 0)
        case .ended:
            // The bar lands where the outline last showed, so what was seen is what happens.
            let target = barDrag?.target
            endBarDrag()
            if let target { setPosition(target) }
        case .cancelled:
            endBarDrag()
        }
    }

    private func endBarDrag() {
        barDragPreview?.orderOut(nil)
        barDragPreview = nil
        barDrag = nil
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
        var order = TaskbarOrdering.merged(order: settings.taskbarAppOrder, adding: pinned + launchOrder)
        if settings.taskbarGroupingEnabled {
            // Every app belongs to a group, and the flat order follows the groups.
            // So turning grouping off later leaves the apps where they are.
            let groups = groupsIncluding(order)
            if groups != settings.taskbarGroups { settings.taskbarGroups = groups }
            order = TaskbarOrdering.merged(order: TaskbarGrouping.order(of: groups), adding: order)
        }
        if order != settings.taskbarAppOrder { settings.taskbarAppOrder = order }

        let pinnedSet = Set(pinned)
        let current = TaskbarOrdering.visible(order: order, pinned: pinnedSet, running: launchOrder).compactMap { id -> TaskbarApp? in
            if let running = runningByID[id] {
                return TaskbarApp(
                    id: id,
                    pid: running.processIdentifier,
                    name: running.localizedName ?? "App",
                    bundleURL: running.bundleURL,
                    icon: id == Bundle.main.bundleIdentifier ? (ownIcon ?? running.icon) : running.icon,
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

        // An app chosen for a display can be a menu bar app, which the list above leaves out.
        // Look those up by bundle identifier so they still show as running.
        var background: [String: TaskbarApp] = [:]
        let chosenIDs = Set(settings.taskbarDisplayRules.filter { $0.mode == .chosenApps }.flatMap(\.appIDs))
        for id in chosenIDs where runningByID[id] == nil {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { !$0.isTerminated })
            else { continue }
            background[id] = TaskbarApp(
                id: id, pid: running.processIdentifier, name: running.localizedName ?? "App",
                bundleURL: running.bundleURL, icon: running.icon,
                isActive: running.processIdentifier == frontPID, isHidden: running.isHidden, isPinned: false
            )
        }
        if background != chosenBackgroundApps { chosenBackgroundApps = background }
    }

    /// This app's icon for the taskbar and App Icon Controls.
    ///
    /// macOS (measured on 27.2.1) serves the small sizes of this app's icon shrunk onto a light
    /// plate, which shows as a white border on the taskbar. The plate is not in the artwork and
    /// is not drawn by the taskbar. So the logo artwork (`AppLogo`) is drawn directly, inset to
    /// the size of a standard icon's body so it lines up with the other apps.
    private static func makeOwnIcon() -> NSImage? {
        guard let logo = NSImage(named: AppInfo.logoAssetName) else { return nil }
        let side: CGFloat = 256
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            logo.draw(in: TaskbarLayout.iconBodyRect(in: rect), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
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

    // MARK: - Groups

    /// The apps as the taskbar shows them: one section per group, or a single section when grouping is off.
    /// App Icon Controls asks for empty groups too, so apps can be dragged into them.
    /// With a display, only the apps that belong on that display's taskbar are included.
    func sections(includingEmpty: Bool, display: UInt32? = nil) -> [TaskbarSection] {
        // A display set to Only Apps I Choose shows that list and nothing else.
        if let display, showsChosenApps(on: display) {
            return [TaskbarSection(id: TaskbarSection.allAppsID, name: "Apps", apps: chosenApps(on: display), isGroup: false)]
        }
        // Hidden apps are not on the bar. They sit behind the Hidden Apps button.
        let hidden = Set(settings.taskbarHiddenApps)
        var shown = hidden.isEmpty ? apps : apps.filter { !hidden.contains($0.id) }
        if let display, tracksWindows {
            let scope = settings.taskbarAppScope
            let bars = scopeBars
            shown = shown.filter { scope.bars(forAppOn: appDisplays[$0.id] ?? [], bars: bars).contains(display) }
        }
        guard settings.taskbarGroupingEnabled else {
            return [TaskbarSection(id: TaskbarSection.allAppsID, name: "Apps", apps: shown, isGroup: false)]
        }
        let appsByID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var grouped = Set<String>()
        var result: [TaskbarSection] = []
        for group in settings.taskbarGroups {
            grouped.formUnion(group.appIDs)
            let members = group.appIDs.compactMap { appsByID[$0] }
            if includingEmpty || !members.isEmpty {
                result.append(TaskbarSection(id: group.id, name: group.name, apps: members, isGroup: true))
            }
        }
        let rest = shown.filter { !grouped.contains($0.id) }
        if !rest.isEmpty {
            result.append(TaskbarSection(id: TaskbarSection.ungroupedID, name: "Not Grouped", apps: rest, isGroup: false))
        }
        return result
    }

    /// What one display's taskbar draws: its apps fitted to the bar's length, and the apps that
    /// did not fit. See `TaskbarFitting` for the steps.
    func content(for display: UInt32) -> TaskbarBarContent {
        let all = sections(includingEmpty: false, display: display)
        let barApps = all.flatMap(\.apps)
        let position = settings.taskbarPosition
        let nameSize = settings.taskbarNameSize.points
        let measuresNames = position.isHorizontal && settings.taskbarShowAppNames && settings.taskbarNamePosition.isBeside
        let isChosenApps = showsChosenApps(on: display)
        let showsButtons = showsButtons(on: display)
        let fit = TaskbarFitting.fit(TaskbarFitRequest(
            barLength: barLengths[display] ?? .greatestFiniteMagnitude,
            isHorizontal: position.isHorizontal,
            iconSize: CGFloat(settings.taskbarIconPoints),
            showNames: settings.taskbarShowAppNames,
            namePosition: settings.taskbarNamePosition,
            nameSize: nameSize,
            sectionCounts: all.map(\.apps.count),
            nameWidths: measuresNames ? barApps.map { nameWidth($0.name, size: nameSize) } : [],
            showsHiddenButton: showsButtons && !hiddenApps.isEmpty,
            showsTrash: showsButtons && settings.taskbarShowTrash,
            showsApplicationsButton: showsButtons
        ))
        guard fit.visibleCount < barApps.count else {
            return TaskbarBarContent(
                sections: all, overflow: [], iconSize: fit.iconSize, showNames: fit.showNames,
                showsButtons: showsButtons, isChosenApps: isChosenApps
            )
        }

        var remaining = fit.visibleCount
        var kept: [TaskbarSection] = []
        for section in all where remaining > 0 {
            let fitting = Array(section.apps.prefix(remaining))
            remaining -= fitting.count
            kept.append(TaskbarSection(id: section.id, name: section.name, apps: fitting, isGroup: section.isGroup))
        }
        return TaskbarBarContent(
            sections: kept,
            overflow: Array(barApps.dropFirst(fit.visibleCount)),
            iconSize: fit.iconSize,
            showNames: fit.showNames,
            showsButtons: showsButtons,
            isChosenApps: isChosenApps
        )
    }

    private func nameWidth(_ name: String, size: CGFloat) -> CGFloat {
        let key = "\(size)|\(name)"
        if let cached = nameWidthCache[key] { return cached }
        let width = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width.rounded(.up)
        nameWidthCache[key] = width
        return width
    }

    // MARK: - Apps per display

    /// True while each taskbar shows only the apps that belong on its display.
    /// With one taskbar, or with every taskbar showing every app, window places are not needed.
    private var tracksWindows: Bool {
        settings.taskbarEnabled && settings.taskbarAppScope != .allTaskbars && scopeBars.count > 1
    }

    /// The taskbars that follow Show Apps On, the main taskbar first. A display set to
    /// Only Apps I Choose is left out, so the first of these always shows the apps with no window.
    private var scopeBars: [UInt32] {
        barDisplays.filter { !showsChosenApps(on: $0) }
    }

    /// Starts or stops watching where windows are, to match the settings.
    private func updateWindowTracking() {
        guard tracksWindows else {
            windowMoveMonitors.forEach(NSEvent.removeMonitor)
            windowMoveMonitors = []
            windowCheck?.cancel()
            windowFollowUp?.cancel()
            if !appDisplays.isEmpty { appDisplays = [:] }
            return
        }
        if windowMoveMonitors.isEmpty {
            // macOS does not announce when another app's window moves. A window only changes
            // displays at the end of a drag or after a click, so the release of the mouse button
            // is the cue to look again. Mouse clicks can be watched without any extra permission.
            let inOtherApps = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleWindowCheck() }
            }
            let inThisApp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                MainActor.assumeIsolated { self?.scheduleWindowCheck() }
                return event
            }
            windowMoveMonitors = [inOtherApps, inThisApp].compactMap { $0 }
        }
        refreshWindowLocations()
    }

    /// Looks where the windows are shortly after a click, and once more a second later for a
    /// window that takes a moment to open. Clicks in quick succession share one look.
    private func scheduleWindowCheck() {
        guard tracksWindows else { return }
        windowCheck?.cancel()
        windowCheck = Task { @MainActor [weak self] in
            for step in [250, 1000] {
                try? await Task.sleep(for: .milliseconds(step))
                if Task.isCancelled { return }
                self?.refreshWindowLocations()
            }
        }
    }

    /// After an app starts or comes forward, its windows appear a little later.
    /// Look a few times over the next seconds, then stop.
    private func followWindowChanges() {
        guard tracksWindows else { return }
        windowFollowUp?.cancel()
        windowFollowUp = Task { @MainActor [weak self] in
            for step in [400, 800, 1500] {
                try? await Task.sleep(for: .milliseconds(step))
                if Task.isCancelled { return }
                self?.refreshWindowLocations()
            }
        }
    }

    /// Works out which displays each running app has windows on.
    ///
    /// An app with no window showing right now (hidden, minimized, on another Space, or with
    /// every window closed) stays where it was last seen. An app that has not shown a window yet
    /// has no entry, and `TaskbarAppScope` puts it on the main taskbar.
    private func refreshWindowLocations() {
        guard tracksWindows else { return }
        let displays: [(id: UInt32, frame: CGRect)] = NSScreen.screens.compactMap { screen in
            Self.displayID(of: screen).map { (id: $0, frame: CGDisplayBounds($0)) }
        }
        let located = WindowLocator.displaysByProcess(windows: WindowLocator.onScreenWindows(), displays: displays)

        var next: [String: Set<UInt32>] = [:]
        var running = Set<String>()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            let id = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            running.insert(id)
            if let found = located[app.processIdentifier] { next[id, default: []].formUnion(found) }
        }
        let connected = Set(displays.map(\.id))
        for (id, last) in appDisplays where next[id] == nil && running.contains(id) {
            let remembered = last.intersection(connected)
            if !remembered.isEmpty { next[id] = remembered }
        }
        guard next != appDisplays else { return }
        appDisplays = next
        updatePopupPanel()
    }

    /// The saved groups with every app in `ids` placed. The first time, all apps are sorted by topic.
    private func groupsIncluding(_ ids: [String]) -> [TaskbarGroup] {
        let saved = settings.taskbarGroups
        if saved.isEmpty {
            return TaskbarGrouping.byTopic(ids) { topic(for: $0) }
        }
        let sortsByTopic = settings.taskbarAutoGroupNewApps
        return TaskbarGrouping.adding(ids, to: saved) { sortsByTopic ? topic(for: $0) : .other }
    }

    /// Works out an app's topic from its bundle identifier and the category it declares.
    private func topic(for bundleID: String) -> AppTopic {
        if let cached = topicCache[bundleID] { return cached }
        let url = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let category = url.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        let topic = AppTopicClassifier.topic(bundleID: bundleID, category: category)
        topicCache[bundleID] = topic
        return topic
    }

    @discardableResult
    private func setGroups(_ groups: [TaskbarGroup]) -> Bool {
        guard groups != settings.taskbarGroups else { return false }
        settings.taskbarGroups = groups
        return true
    }

    /// Sorts every app into topic groups again. This replaces the groups the user made.
    func regroupByTopic() {
        setGroups(TaskbarGrouping.byTopic(settings.taskbarAppOrder) { topic(for: $0) })
    }

    /// Adds an empty group and returns its identifier. It goes ahead of Other, so Other stays last.
    @discardableResult
    func addGroup() -> String {
        var groups = settings.taskbarGroups
        let group = TaskbarGroup(name: TaskbarGrouping.uniqueName("New Group", in: groups))
        if groups.last?.id == AppTopic.other.groupID {
            groups.insert(group, at: groups.count - 1)
        } else {
            groups.append(group)
        }
        setGroups(groups)
        return group.id
    }

    func renameGroup(_ id: String, to name: String) {
        var groups = settings.taskbarGroups
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        setGroups(groups)
    }

    func canDeleteGroup(_ id: String) -> Bool {
        TaskbarGrouping.canRemoveGroup(id, from: settings.taskbarGroups)
    }

    /// Removes a group. Its apps move to Other.
    func deleteGroup(_ id: String) {
        setGroups(TaskbarGrouping.removingGroup(id, from: settings.taskbarGroups))
    }

    /// Moves a group up (negative) or down (positive).
    func shiftGroup(_ id: String, by offset: Int) {
        setGroups(TaskbarGrouping.shiftingGroup(id, by: offset, in: settings.taskbarGroups))
    }

    /// Moves an app to the end of a group.
    func moveApp(_ id: String, toGroup groupID: String) {
        setGroups(TaskbarGrouping.moving(id, toGroup: groupID, in: settings.taskbarGroups))
    }

    /// Keeps the chosen apps on the taskbar and, when grouping is on, puts them in a group.
    func addApps(at urls: [URL], toGroup groupID: String?) {
        var pinned = settings.taskbarPinnedApps
        var groups = settings.taskbarGroups
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            if !pinned.contains(id) { pinned.append(id) }
            if settings.taskbarGroupingEnabled, let groupID {
                groups = TaskbarGrouping.moving(id, toGroup: groupID, in: groups)
            }
        }
        setGroups(groups)
        if pinned != settings.taskbarPinnedApps { settings.taskbarPinnedApps = pinned }
    }

    /// Add Icons in the taskbar's right-click menu. The person picks apps in a file chooser and
    /// they stay on the taskbar, running or not. On a display that shows only its chosen apps,
    /// they join that display's apps.
    func chooseAppsToAdd(on displayID: UInt32) {
        closePopup()
        // Wait a turn, so the right-click menu has closed before the file chooser opens.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let chosenDisplay = self.displays.first { $0.id == displayID && self.showsChosenApps(on: $0.id) }
            let panel = NSOpenPanel()
            panel.title = chosenDisplay.map { "Add Icons to the \($0.name) Taskbar" } ?? "Add Icons to the Taskbar"
            panel.message = "Choose the apps to keep on the taskbar."
            panel.prompt = "Add"
            panel.allowedContentTypes = [.applicationBundle]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            // The taskbar never takes the keyboard, so bring this app forward for the chooser.
            NSApp.activate()
            guard panel.runModal() == .OK else { return }
            if let chosenDisplay {
                self.addChosenApps(at: panel.urls, to: chosenDisplay)
            } else {
                self.addApps(at: panel.urls, toGroup: nil)
            }
        }
    }

    // MARK: - Apps from the Apple Dock and from Finder

    /// The apps kept in the macOS Dock that this display's taskbar does not keep yet, in the
    /// Dock's order. Apps that are no longer installed are left out.
    func appleDockAppsToAdd(on displayID: UInt32) -> [DockApp] {
        let kept = Set(keptAppIDs(on: displayID))
        return DockInfo.keptApps.filter { app in
            !kept.contains(app.bundleID) && installedApp(for: app.bundleID) != nil
        }
    }

    /// The apps this display's taskbar keeps whether they are running or not.
    private func keptAppIDs(on displayID: UInt32) -> [String] {
        if showsChosenApps(on: displayID) { return rule(for: displayID)?.appIDs ?? [] }
        return settings.taskbarPinnedApps
    }

    /// Keeps apps on the taskbar by bundle identifier. On a display that shows only its chosen
    /// apps, they join that display's apps. Used by Add from Apple Dock.
    func addApps(withIDs ids: [String], on displayID: UInt32) {
        let ids = ids.filter { !$0.hasPrefix("pid:") }
        guard !ids.isEmpty else { return }
        if let display = displays.first(where: { $0.id == displayID }), showsChosenApps(on: displayID) {
            setDisplayRules(TaskbarDisplayRules.adding(ids, to: display.key, name: display.name, in: settings.taskbarDisplayRules))
            return
        }
        var pinned = settings.taskbarPinnedApps
        for id in ids where !pinned.contains(id) { pinned.append(id) }
        if pinned != settings.taskbarPinnedApps { settings.taskbarPinnedApps = pinned }
    }

    /// The apps among dropped files, with their bundle identifiers. Anything that is not an app
    /// is left out, and an app dropped twice counts once.
    static func droppedApps(_ urls: [URL], bundleID: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }) -> [String] {
        var seen = Set<String>()
        return urls.compactMap { url in
            guard url.isFileURL, url.pathExtension.lowercased() == "app",
                  let id = bundleID(url), !id.isEmpty, seen.insert(id).inserted
            else { return nil }
            return id
        }
    }

    /// Adds apps dropped on a taskbar as files, for example dragged from the Applications folder
    /// in Finder. With a target, they land right before or after that app. Without one, they go
    /// to the end. Returns how many apps were in the drop.
    @discardableResult
    func addDroppedApps(at urls: [URL], on displayID: UInt32, beside target: (id: String, before: Bool)? = nil) -> Int {
        let ids = Self.droppedApps(urls)
        guard !ids.isEmpty else { return 0 }
        // Placed one at a time next to the target. Going backward for "after" keeps their order.
        let placingOrder = target?.before == false ? Array(ids.reversed()) : ids

        if let display = displays.first(where: { $0.id == displayID }), showsChosenApps(on: displayID) {
            var rules = TaskbarDisplayRules.adding(ids, to: display.key, name: display.name, in: settings.taskbarDisplayRules)
            if let target {
                for id in placingOrder {
                    rules = TaskbarDisplayRules.placing(
                        id, before: target.before, target: target.id, on: display.key, name: display.name, in: rules
                    )
                }
            }
            setDisplayRules(rules)
            return ids.count
        }

        addApps(withIDs: ids, on: displayID)
        // Gives each new app its place in the order, and its group when grouping is on.
        reloadApps()
        for id in placingOrder {
            if let target {
                draggedAppID = id
                placeDraggedApp(before: target.before, targetID: target.id)
            } else {
                // An app the person had tucked away comes back when they drop it on the bar.
                setHiddenFromTaskbar(false, appID: id)
            }
        }
        draggedAppID = nil
        return ids.count
    }

    // MARK: - Apps chosen per display

    /// What the person set up for one display's taskbar, if anything.
    func rule(for display: UInt32) -> TaskbarDisplayRule? {
        guard let key = displays.first(where: { $0.id == display })?.key else { return nil }
        return TaskbarDisplayRules.rule(for: key, in: settings.taskbarDisplayRules)
    }

    /// True when this display's taskbar shows only the apps chosen for it.
    func showsChosenApps(on display: UInt32) -> Bool {
        rule(for: display)?.mode == .chosenApps
    }

    /// Whether this display's taskbar has the Applications, Hidden Apps, and Trash buttons.
    /// Always true unless the display shows only its chosen apps and the buttons were turned off.
    func showsButtons(on display: UInt32) -> Bool {
        guard let rule = rule(for: display), rule.mode == .chosenApps else { return true }
        return rule.showsButtons
    }

    /// The displays set to Only Apps I Choose. The right-click menu offers them under Show on Display.
    var chosenDisplays: [TaskbarDisplay] {
        displays.filter { showsChosenApps(on: $0.id) }
    }

    /// The apps chosen for a display, in its order. They show whether they are running or not.
    /// An app that is no longer installed is left out.
    func chosenApps(on display: UInt32) -> [TaskbarApp] {
        guard let rule = rule(for: display), rule.mode == .chosenApps else { return [] }
        let appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rule.appIDs.compactMap { id in
            if let app = appsByID[id] ?? chosenBackgroundApps[id] { return app }
            guard let installed = installedApp(for: id) else { return nil }
            return TaskbarApp(
                id: id, pid: nil, name: installed.name, bundleURL: installed.url,
                icon: id == Bundle.main.bundleIdentifier ? (ownIcon ?? installed.icon) : installed.icon,
                isActive: false, isHidden: false, isPinned: false
            )
        }
    }

    func setAppMode(_ mode: TaskbarDisplayAppMode, for display: TaskbarDisplay) {
        changeRule(for: display) { $0.mode = mode }
    }

    func setShowsButtons(_ shows: Bool, for display: TaskbarDisplay) {
        changeRule(for: display) { $0.showsButtons = shows }
    }

    func isChosen(_ appID: String, on display: TaskbarDisplay) -> Bool {
        TaskbarDisplayRules.rule(for: display.key, in: settings.taskbarDisplayRules)?.appIDs.contains(appID) ?? false
    }

    /// Adds an app to a display's chosen apps, or takes it off.
    func setChosen(_ chosen: Bool, appID: String, on display: TaskbarDisplay) {
        let rules = settings.taskbarDisplayRules
        setDisplayRules(chosen
            ? TaskbarDisplayRules.adding([appID], to: display.key, name: display.name, in: rules)
            : TaskbarDisplayRules.removing(appID, from: display.key, in: rules))
    }

    /// Adds the apps picked in the file chooser to a display's chosen apps.
    func addChosenApps(at urls: [URL], to display: TaskbarDisplay) {
        let ids = urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        setDisplayRules(TaskbarDisplayRules.adding(ids, to: display.key, name: display.name, in: settings.taskbarDisplayRules))
    }

    /// Adds the app that is being dragged to a display's chosen apps, when it is dropped on the
    /// display's taskbar or its card in App Icon Controls and not on another app.
    @discardableResult
    func addDraggedApp(toChosenDisplay displayID: UInt32) -> Bool {
        guard let dragged = draggedAppID, let display = displays.first(where: { $0.id == displayID }),
              showsChosenApps(on: displayID)
        else { return false }
        return setDisplayRules(TaskbarDisplayRules.adding([dragged], to: display.key, name: display.name, in: settings.taskbarDisplayRules))
    }

    /// Puts the dragged app before or after a chosen app on one display. An app dragged in from
    /// another taskbar or from the groups joins that display's chosen apps.
    @discardableResult
    func placeDraggedApp(before: Bool, targetID: String, onChosenDisplay displayID: UInt32) -> Bool {
        guard let dragged = draggedAppID, let display = displays.first(where: { $0.id == displayID }) else { return false }
        return setDisplayRules(TaskbarDisplayRules.placing(
            dragged, before: before, target: targetID, on: display.key, name: display.name, in: settings.taskbarDisplayRules
        ))
    }

    /// True while the app being dragged is already one of the display's chosen apps, so the drag
    /// is a reorder and not an app coming in from somewhere else.
    func isChosenDrag(on display: TaskbarDisplay) -> Bool {
        guard let dragged = draggedAppID else { return false }
        return isChosen(dragged, on: display)
    }

    func isChosenDrag(onDisplayID displayID: UInt32) -> Bool {
        guard let display = displays.first(where: { $0.id == displayID }) else { return false }
        return isChosenDrag(on: display)
    }

    private func changeRule(for display: TaskbarDisplay, _ change: (inout TaskbarDisplayRule) -> Void) {
        setDisplayRules(TaskbarDisplayRules.updating(display.key, name: display.name, in: settings.taskbarDisplayRules, change))
    }

    @discardableResult
    private func setDisplayRules(_ rules: [TaskbarDisplayRule]) -> Bool {
        guard rules != settings.taskbarDisplayRules else { return false }
        settings.taskbarDisplayRules = rules
        return true
    }

    // MARK: - Dragging

    func beginAppDrag(_ id: String) {
        draggedAppID = id
        draggedGroupID = nil
    }

    func beginGroupDrag(_ id: String) {
        draggedGroupID = id
        draggedAppID = nil
    }

    func endDrag() {
        draggedAppID = nil
        draggedGroupID = nil
    }

    /// Puts the dragged app before or after the app the pointer is over, and saves the new order.
    /// With grouping on, the app also joins the group of the app it lands next to.
    /// Returns true if the order changed.
    ///
    /// Hidden apps follow the same rule: dropped next to a hidden app, the dragged app becomes
    /// hidden too, and dropped next to an app on the bar, a hidden app comes back.
    @discardableResult
    func placeDraggedApp(before: Bool, targetID: String) -> Bool {
        guard let dragged = draggedAppID, dragged != targetID else { return false }
        let hidden = settings.taskbarHiddenApps
        if hidden.contains(targetID) {
            let placed = TaskbarOrdering.placingHidden(dragged, before: before, target: targetID, in: hidden)
            guard placed != hidden else { return false }
            settings.taskbarHiddenApps = placed
            return true
        }

        let cameBack = hidden.contains(dragged)
        if cameBack { settings.taskbarHiddenApps = hidden.filter { $0 != dragged } }

        if settings.taskbarGroupingEnabled {
            let moved = setGroups(TaskbarGrouping.placing(dragged, before: before, target: targetID, in: settings.taskbarGroups))
            return moved || cameBack
        }
        let order = TaskbarOrdering.placing(dragged, before: before, target: targetID, in: settings.taskbarAppOrder)
        guard order != settings.taskbarAppOrder else { return cameBack }
        settings.taskbarAppOrder = order
        return true
    }

    /// Moves the dragged app to the end of a group, when it is dropped on the group and not on an app.
    /// A hidden app comes back to the bar.
    @discardableResult
    func moveDraggedApp(toGroup groupID: String) -> Bool {
        guard let dragged = draggedAppID else { return false }
        let cameBack = setHiddenFromTaskbar(false, appID: dragged)
        let moved = setGroups(TaskbarGrouping.moving(dragged, toGroup: groupID, in: settings.taskbarGroups))
        return moved || cameBack
    }

    /// Moves the dragged group into the spot of the group the pointer is over.
    @discardableResult
    func placeDraggedGroup(at targetID: String) -> Bool {
        guard let dragged = draggedGroupID else { return false }
        return setGroups(TaskbarGrouping.placingGroup(dragged, at: targetID, in: settings.taskbarGroups))
    }

    // MARK: - Hidden apps

    /// Apps tucked behind the Hidden Apps button that are running or kept, in the order the pop-up shows them.
    var hiddenApps: [TaskbarApp] {
        let hidden = settings.taskbarHiddenApps
        guard !hidden.isEmpty else { return [] }
        let appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return hidden.compactMap { appsByID[$0] }
    }

    /// The number on the Hidden Apps button.
    var runningHiddenCount: Int {
        hiddenApps.filter(\.isRunning).count
    }

    func isHiddenFromTaskbar(_ appID: String) -> Bool {
        settings.taskbarHiddenApps.contains(appID)
    }

    /// Hide from Taskbar, or Show in Taskbar. A hidden app keeps running and keeps its place for later.
    @discardableResult
    func setHiddenFromTaskbar(_ hidden: Bool, appID: String) -> Bool {
        guard !appID.hasPrefix("pid:") else { return false }
        var list = settings.taskbarHiddenApps
        if hidden {
            guard !list.contains(appID) else { return false }
            list.append(appID)
        } else {
            guard list.contains(appID) else { return false }
            list.removeAll { $0 == appID }
        }
        settings.taskbarHiddenApps = list
        return true
    }

    /// Hides or shows the app that is being dragged, when it is dropped on the Hidden Apps button
    /// or on a group and not on another app.
    @discardableResult
    func setDraggedAppHidden(_ hidden: Bool) -> Bool {
        guard let dragged = draggedAppID else { return false }
        return setHiddenFromTaskbar(hidden, appID: dragged)
    }

    /// Puts every hidden app back on the bar.
    func showAllHiddenApps() {
        if !settings.taskbarHiddenApps.isEmpty { settings.taskbarHiddenApps = [] }
    }

    /// The symbol for the Hidden Apps button. Falls back to one every supported macOS has.
    var hiddenIconSymbolName: String {
        let name = settings.taskbarHiddenIcon.symbolName
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? HiddenAppsIcon.stack.symbolName : name
    }

    /// True while the Hidden Apps pop-up is open.
    var isHiddenAppsShown: Bool { shownPopup == .hiddenApps }

    /// The apps a pop-up holds.
    func apps(in popup: TaskbarPopup) -> [TaskbarApp] {
        switch popup {
        case .hiddenApps: hiddenApps
        case .moreApps(let display): content(for: display).overflow
        }
    }

    /// Opens a pop-up next to its button, or closes it if it is already open.
    /// `anchor` is the button's frame in screen coordinates.
    func togglePopup(_ popup: TaskbarPopup, anchor: NSRect?) {
        if popupPanel != nil {
            let wasOpen = shownPopup == popup
            closePopup()
            if wasOpen { return }
        }
        guard !apps(in: popup).isEmpty else { return }
        // Without a button frame (for example when VoiceOver presses the button), use the end of the taskbar.
        let bar: TaskbarPanel? = switch popup {
        case .hiddenApps: panels.values.first
        case .moreApps(let display): panels[display]
        }
        popupAnchor = anchor ?? bar.map { bar in
            let side = thickness
            return settings.taskbarPosition.isHorizontal
                ? NSRect(x: bar.frame.maxX - 2 * side, y: bar.frame.minY, width: side, height: bar.frame.height)
                : NSRect(x: bar.frame.minX, y: bar.frame.minY + side, width: bar.frame.width, height: side)
        }
        guard let frame = popupFrame(for: popup) else {
            popupAnchor = nil
            return
        }

        let panel = TaskbarPanel(rootView: TaskbarPopupView(controller: self, popup: popup))
        panel.hasShadow = true
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        popupPanel = panel
        shownPopup = popup
        installOutsideClickMonitors()
    }

    func closePopup() {
        guard let panel = popupPanel else { return }
        panel.orderOut(nil)
        popupPanel = nil
        popupAnchor = nil
        shownPopup = nil
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors = []
    }

    /// Keeps an open pop-up the right size and in the right place. Closes it when nothing is left to show.
    private func updatePopupPanel() {
        guard let panel = popupPanel, let popup = shownPopup else { return }
        guard !apps(in: popup).isEmpty, let frame = popupFrame(for: popup) else {
            closePopup()
            return
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func popupFrame(for popup: TaskbarPopup) -> NSRect? {
        guard let anchor = popupAnchor else { return nil }
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        guard let bar = panels.values.first(where: { $0.frame.contains(center) }),
              let screen = bar.screen ?? NSScreen.main
        else { return nil }
        let size = TaskbarLayout.hiddenPopupSize(count: apps(in: popup).count, iconSize: CGFloat(settings.taskbarIconPoints))
        return TaskbarLayout.hiddenPopupFrame(
            size: size, anchor: anchor, bar: bar.frame, screen: screen.frame, position: settings.taskbarPosition
        )
    }

    /// A click anywhere outside the pop-up and the taskbars closes the pop-up, like a menu.
    /// Mouse clicks can be watched without any extra permission.
    private func installOutsideClickMonitors() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let inOtherApps = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopup() }
        }
        let inThisApp = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated {
                if !(event.window is TaskbarPanel) { self?.closePopup() }
            }
            return event
        }
        outsideClickMonitors = [inOtherApps, inThisApp].compactMap { $0 }
    }

    // MARK: - Apple Dock or taskbar

    /// The taskbar when it is showing, otherwise the Apple Dock.
    var barMode: BarMode {
        settings.taskbarEnabled ? .taskbar : .appleDock
    }

    /// One switch between this app's taskbar and the Apple Dock.
    ///
    /// Going to the Apple Dock hides the taskbar and, if this app had turned the Dock off, brings
    /// the Dock back. Going to the taskbar shows it again and turns the Dock off again if it was
    /// off before. So one switch always puts things back the way they were.
    func switchBar(to mode: BarMode) {
        switch mode {
        case .appleDock:
            refreshDockState()
            settings.taskbarTurnsDockOff = isDockTurnedOff
            if isDockTurnedOff { setDockTurnedOff(false) }
            if settings.taskbarEnabled { settings.taskbarEnabled = false }
        case .taskbar:
            if !settings.taskbarEnabled { settings.taskbarEnabled = true }
            refreshDockState()
            if settings.taskbarTurnsDockOff, !isDockTurnedOff { setDockTurnedOff(true) }
        }
    }

    func toggleBar() {
        switchBar(to: barMode == .taskbar ? .appleDock : .taskbar)
    }

    // MARK: - Taskbar actions

    /// Opens an app that is not running, or brings a running app to the front. Clicking the app
    /// that is already in front hides it, like clicking the active app on the Windows taskbar.
    func activate(_ app: TaskbarApp) {
        closePopup()
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
        if list != settings.taskbarPinnedApps { settings.taskbarPinnedApps = list }
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

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    /// Opens the main window on one of the taskbar's settings screens.
    func openSettings(_ item: SidebarItem = .taskbar) {
        closePopup()
        showSettings?(item)
    }

    // MARK: - Trash and disks

    /// Opens the Trash in Finder.
    func openTrash() {
        trash.refresh()
        guard let url = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Asks first, then has Finder empty the Trash. Finder does the deleting, the same as its own
    /// Empty Trash command. The first use shows the macOS prompt asking to let this app control Finder.
    func emptyTrash() {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Everything in the Trash is deleted for good. This cannot be undone."
        // Cancel is first, so pressing Return never deletes anything.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Empty Trash").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        // The person has already confirmed above, so Finder's own warning is switched off for this
        // one command and then put back the way it was.
        let source = """
        with timeout of 120 seconds
            tell application "Finder"
                set wasWarning to missing value
                try
                    set wasWarning to warns before emptying of trash
                    set warns before emptying of trash to false
                end try
                try
                    empty trash
                on error errorText number errorNumber
                    try
                        if wasWarning is not missing value then set warns before emptying of trash to wasWarning
                    end try
                    error errorText number errorNumber
                end try
                try
                    if wasWarning is not missing value then set warns before emptying of trash to wasWarning
                end try
            end tell
        end timeout
        """
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        // Finder may have emptied all of it, some of it, or none of it. Show what is left.
        trash.refresh()
        guard let errorInfo else { return }

        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        let message: String
        switch code {
        case -1743:
            message = "macOS is blocking access to Finder. Allow it in System Settings, Privacy & Security, Automation."
        case -1712:
            message = "Finder is taking a long time. It may still be emptying the Trash."
        case -600:
            message = "Finder is not running."
        default:
            let detail = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            message = "Finder returned an error: \(detail)"
        }
        showNotice(title: "The Trash could not be emptied.", message: message)
    }

    /// Lists the disks that can be ejected. The startup disk and other built-in volumes are left out.
    func refreshVolumes() {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
            .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let volumes = urls.compactMap { url -> EjectableVolume? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsRootFileSystem != true else { return nil }
            let canEject = values.volumeIsEjectable == true || values.volumeIsRemovable == true
                || values.volumeIsInternal == false || values.volumeIsLocal == false
            guard canEject else { return nil }
            return EjectableVolume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent)
        }
        if volumes != ejectableVolumes { ejectableVolumes = volumes }
    }

    /// Unmounts a disk and ejects it. If an app is still using the disk, macOS shows its own message.
    func eject(_ volume: EjectableVolume) {
        FileManager.default.unmountVolume(at: volume.url, options: [.allPartitionsAndEjectDisk]) { _ in }
    }

    func ejectAll() {
        ejectableVolumes.forEach(eject)
    }

    private func showNotice(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
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

    /// Called as the app quits. A Dock that this app turned off comes back, so the Mac is never
    /// left with no Dock and no taskbar. The next launch turns it off again.
    func restoreDockForQuit() {
        guard !AppInfo.isRunningTests else { return }
        refreshDockState()
        guard isDockTurnedOff else { return }
        settings.dockOffAgainAtLaunch = true
        setDockTurnedOff(false)
    }

    /// The other half of `restoreDockForQuit`: the Dock was off when the app last quit, so it
    /// goes off again now that the app is back.
    private func turnDockOffAgainAfterLaunch() {
        guard !AppInfo.isRunningTests, settings.dockOffAgainAtLaunch else { return }
        settings.dockOffAgainAtLaunch = false
        refreshDockState()
        if !isDockTurnedOff { setDockTurnedOff(true) }
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
