import Foundation
import Observation

/// All persistent preferences, stored in UserDefaults.
/// Views bind to these properties. Controllers react to `.appSettingsDidChange`.
@MainActor
@Observable
final class AppSettings {
    enum Key: String, CaseIterable {
        case windowManagerEnabled = "windowManager.enabled"
        case maximizeEnabled = "windowManager.maximizeEnabled"
        case greenButtonEnabled = "windowManager.greenButtonEnabled"
        case snappingEnabled = "windowManager.snappingEnabled"
        case windowShortcutsEnabled = "windowManager.shortcutsEnabled"
        case shortcuts = "windowManager.shortcuts"
        case finderEnabled = "finder.enabled"
        case desktopEnabled = "desktop.enabled"
        case desktopSortOrder = "desktop.sortOrder"
        case showMenuBarIcon = "general.showMenuBarIcon"
        case hasDonated = "general.hasDonated"
        case taskbarEnabled = "taskbar.enabled"
        case taskbarDisplayMode = "taskbar.displayMode"
        case taskbarAppScope = "taskbar.appScope"
        case taskbarShowAppNames = "taskbar.showAppNames"
        case taskbarReserveSpace = "taskbar.reserveSpace"
        case taskbarPosition = "taskbar.position"
        /// Version 1.0 icon size: "small", "medium", or "large". Only read, to carry the choice over.
        case taskbarIconSize = "taskbar.iconSize"
        case taskbarIconPoints = "taskbar.iconPoints"
        case taskbarNamePosition = "taskbar.namePosition"
        case taskbarGlassBackground = "taskbar.glassBackground"
        case taskbarCornerStyle = "taskbar.cornerStyle"
        case taskbarNameSize = "taskbar.nameSize"
        case taskbarShowTrash = "taskbar.showTrash"
        case taskbarPinnedApps = "taskbar.pinnedApps"
        case taskbarAppOrder = "taskbar.appOrder"
        case taskbarGroupingEnabled = "taskbar.groupingEnabled"
        case taskbarAutoGroupNewApps = "taskbar.autoGroupNewApps"
        case taskbarGroups = "taskbar.groups"
        case taskbarHiddenApps = "taskbar.hiddenApps"
        case taskbarHiddenIcon = "taskbar.hiddenIcon"
        case taskbarDisplayRules = "taskbar.displayRules"
        case taskbarTurnsDockOff = "taskbar.turnsDockOff"
        case dockAutoHideBeforeOff = "dock.autoHideBeforeOff"
        case dockOffAgainAtLaunch = "dock.offAgainAtLaunch"
    }

    // Window Manager
    var windowManagerEnabled: Bool { didSet { store(windowManagerEnabled, .windowManagerEnabled) } }
    var maximizeEnabled: Bool { didSet { store(maximizeEnabled, .maximizeEnabled) } }
    var greenButtonEnabled: Bool { didSet { store(greenButtonEnabled, .greenButtonEnabled) } }
    var snappingEnabled: Bool { didSet { store(snappingEnabled, .snappingEnabled) } }
    var windowShortcutsEnabled: Bool { didSet { store(windowShortcutsEnabled, .windowShortcutsEnabled) } }
    /// Keyboard shortcuts by action. A missing action means "no shortcut".
    var shortcuts: [ShortcutAction: KeyCombo] { didSet { storeShortcuts() } }

    // Finder Enhancements
    var finderEnabled: Bool { didSet { store(finderEnabled, .finderEnabled) } }

    // Desktop Manager
    var desktopEnabled: Bool { didSet { store(desktopEnabled, .desktopEnabled) } }
    var desktopSortOrder: DesktopSortOrder { didSet { store(desktopSortOrder.rawValue, .desktopSortOrder) } }

    // Taskbar
    var taskbarEnabled: Bool { didSet { store(taskbarEnabled, .taskbarEnabled) } }
    var taskbarDisplayMode: TaskbarDisplayMode { didSet { store(taskbarDisplayMode.rawValue, .taskbarDisplayMode) } }
    /// Which taskbars an app shows on when more than one display has a taskbar.
    var taskbarAppScope: TaskbarAppScope { didSet { store(taskbarAppScope.rawValue, .taskbarAppScope) } }
    var taskbarShowAppNames: Bool { didSet { store(taskbarShowAppNames, .taskbarShowAppNames) } }
    /// Which edge of each display the taskbar uses. Independent of the macOS Dock.
    var taskbarPosition: TaskbarPosition { didSet { store(taskbarPosition.rawValue, .taskbarPosition) } }
    /// Size of the app icons in points. See `TaskbarIconScale` for the range.
    var taskbarIconPoints: Double { didSet { store(taskbarIconPoints, .taskbarIconPoints) } }
    /// Where an app's name sits relative to its icon.
    var taskbarNamePosition: TaskbarNamePosition { didSet { store(taskbarNamePosition.rawValue, .taskbarNamePosition) } }
    /// Translucent glass look when on, solid bar when off.
    var taskbarGlassBackground: Bool { didSet { store(taskbarGlassBackground, .taskbarGlassBackground) } }
    var taskbarCornerStyle: TaskbarCornerStyle { didSet { store(taskbarCornerStyle.rawValue, .taskbarCornerStyle) } }
    var taskbarNameSize: TaskbarNameSize { didSet { store(taskbarNameSize.rawValue, .taskbarNameSize) } }
    var taskbarShowTrash: Bool { didSet { store(taskbarShowTrash, .taskbarShowTrash) } }
    /// Bundle identifiers of apps kept on the taskbar even when they are not running.
    var taskbarPinnedApps: [String] { didSet { store(taskbarPinnedApps, .taskbarPinnedApps) } }
    /// Bundle identifiers in the order the user arranged them. Apps keep their spot between launches.
    var taskbarAppOrder: [String] { didSet { store(taskbarAppOrder, .taskbarAppOrder) } }
    /// When on, the taskbar shows apps in groups with a divider between them.
    var taskbarGroupingEnabled: Bool { didSet { store(taskbarGroupingEnabled, .taskbarGroupingEnabled) } }
    /// When on, an app seen for the first time goes into the group for its topic. When off, it goes into Other.
    var taskbarAutoGroupNewApps: Bool { didSet { store(taskbarAutoGroupNewApps, .taskbarAutoGroupNewApps) } }
    /// The groups, in the order they show. Only used while grouping is on.
    var taskbarGroups: [TaskbarGroup] { didSet { storeGroups() } }
    /// Bundle identifiers of apps tucked behind the Hidden Apps button, in the order the pop-up shows them.
    var taskbarHiddenApps: [String] { didSet { store(taskbarHiddenApps, .taskbarHiddenApps) } }
    var taskbarHiddenIcon: HiddenAppsIcon { didSet { store(taskbarHiddenIcon.rawValue, .taskbarHiddenIcon) } }
    /// What each display's taskbar shows when it was set up by hand. Displays not listed follow `taskbarAppScope`.
    var taskbarDisplayRules: [TaskbarDisplayRule] { didSet { storeDisplayRules() } }
    /// True when the Dock was turned off the last time the taskbar was in use.
    /// Switching back to the taskbar then turns the Dock off again.
    var taskbarTurnsDockOff: Bool { didSet { store(taskbarTurnsDockOff, .taskbarTurnsDockOff) } }
    /// What the Dock's auto-hide setting was before the Dock was turned off, so it can be put back.
    var dockAutoHideBeforeOff: Bool { didSet { store(dockAutoHideBeforeOff, .dockAutoHideBeforeOff) } }
    /// True when the Dock was off as the app quit. The app brings the Dock back on the way out
    /// and turns it off again at the next launch.
    var dockOffAgainAtLaunch: Bool { didSet { store(dockOffAgainAtLaunch, .dockOffAgainAtLaunch) } }
    /// When on, Window Manager keeps maximized and snapped windows clear of the taskbar.
    var taskbarReserveSpace: Bool { didSet { store(taskbarReserveSpace, .taskbarReserveSpace) } }

    // General
    var showMenuBarIcon: Bool { didSet { store(showMenuBarIcon, .showMenuBarIcon) } }
    /// Turned on by the person to say they have donated. Honor system: nothing checks it and
    /// nothing is sent. It only swaps the Donate button for a thank-you.
    var hasDonated: Bool { didSet { store(hasDonated, .hasDonated) } }

    private let defaults: UserDefaults
    /// True while many settings change together. See `batch`.
    @ObservationIgnored private var isBatching = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.windowManagerEnabled.rawValue: true,
            Key.maximizeEnabled.rawValue: true,
            Key.greenButtonEnabled.rawValue: false,
            Key.snappingEnabled.rawValue: true,
            Key.windowShortcutsEnabled.rawValue: true,
            Key.finderEnabled.rawValue: true,
            Key.desktopEnabled.rawValue: true,
            Key.desktopSortOrder.rawValue: DesktopSortOrder.name.rawValue,
            Key.showMenuBarIcon.rawValue: true,
            Key.taskbarEnabled.rawValue: false,
            Key.taskbarDisplayMode.rawValue: TaskbarDisplayMode.allDisplays.rawValue,
            Key.taskbarAppScope.rawValue: TaskbarAppScope.allTaskbars.rawValue,
            Key.taskbarShowAppNames.rawValue: true,
            Key.taskbarReserveSpace.rawValue: true,
            Key.taskbarPosition.rawValue: TaskbarPosition.bottom.rawValue,
            Key.taskbarNamePosition.rawValue: TaskbarNamePosition.right.rawValue,
            Key.taskbarGlassBackground.rawValue: true,
            Key.taskbarCornerStyle.rawValue: TaskbarCornerStyle.square.rawValue,
            Key.taskbarNameSize.rawValue: TaskbarNameSize.small.rawValue,
            Key.taskbarShowTrash.rawValue: true,
            Key.taskbarGroupingEnabled.rawValue: false,
            Key.taskbarAutoGroupNewApps.rawValue: true,
        ])

        windowManagerEnabled = defaults.bool(forKey: Key.windowManagerEnabled.rawValue)
        maximizeEnabled = defaults.bool(forKey: Key.maximizeEnabled.rawValue)
        greenButtonEnabled = defaults.bool(forKey: Key.greenButtonEnabled.rawValue)
        snappingEnabled = defaults.bool(forKey: Key.snappingEnabled.rawValue)
        windowShortcutsEnabled = defaults.bool(forKey: Key.windowShortcutsEnabled.rawValue)
        shortcuts = Self.loadShortcuts(from: defaults)
        finderEnabled = defaults.bool(forKey: Key.finderEnabled.rawValue)
        desktopEnabled = defaults.bool(forKey: Key.desktopEnabled.rawValue)
        desktopSortOrder = DesktopSortOrder(rawValue: defaults.string(forKey: Key.desktopSortOrder.rawValue) ?? "") ?? .name
        taskbarEnabled = defaults.bool(forKey: Key.taskbarEnabled.rawValue)
        taskbarDisplayMode = TaskbarDisplayMode(rawValue: defaults.string(forKey: Key.taskbarDisplayMode.rawValue) ?? "") ?? .allDisplays
        taskbarAppScope = TaskbarAppScope(rawValue: defaults.string(forKey: Key.taskbarAppScope.rawValue) ?? "") ?? .allTaskbars
        taskbarShowAppNames = defaults.bool(forKey: Key.taskbarShowAppNames.rawValue)
        taskbarReserveSpace = defaults.bool(forKey: Key.taskbarReserveSpace.rawValue)
        taskbarPosition = TaskbarPosition(rawValue: defaults.string(forKey: Key.taskbarPosition.rawValue) ?? "") ?? .bottom
        taskbarIconPoints = TaskbarIconScale.clamped(
            (defaults.object(forKey: Key.taskbarIconPoints.rawValue) as? Double)
                ?? TaskbarIconScale.points(forLegacySize: defaults.string(forKey: Key.taskbarIconSize.rawValue))
        )
        taskbarNamePosition = TaskbarNamePosition(rawValue: defaults.string(forKey: Key.taskbarNamePosition.rawValue) ?? "") ?? .right
        taskbarGlassBackground = defaults.bool(forKey: Key.taskbarGlassBackground.rawValue)
        taskbarCornerStyle = TaskbarCornerStyle(rawValue: defaults.string(forKey: Key.taskbarCornerStyle.rawValue) ?? "") ?? .square
        taskbarNameSize = TaskbarNameSize(rawValue: defaults.string(forKey: Key.taskbarNameSize.rawValue) ?? "") ?? .small
        taskbarShowTrash = defaults.bool(forKey: Key.taskbarShowTrash.rawValue)
        taskbarPinnedApps = defaults.stringArray(forKey: Key.taskbarPinnedApps.rawValue) ?? []
        taskbarAppOrder = defaults.stringArray(forKey: Key.taskbarAppOrder.rawValue) ?? []
        taskbarGroupingEnabled = defaults.bool(forKey: Key.taskbarGroupingEnabled.rawValue)
        taskbarAutoGroupNewApps = defaults.bool(forKey: Key.taskbarAutoGroupNewApps.rawValue)
        taskbarGroups = Self.loadGroups(from: defaults)
        taskbarHiddenApps = defaults.stringArray(forKey: Key.taskbarHiddenApps.rawValue) ?? []
        taskbarHiddenIcon = HiddenAppsIcon(rawValue: defaults.string(forKey: Key.taskbarHiddenIcon.rawValue) ?? "") ?? .sunglasses
        taskbarDisplayRules = Self.loadDisplayRules(from: defaults)
        taskbarTurnsDockOff = defaults.bool(forKey: Key.taskbarTurnsDockOff.rawValue)
        dockAutoHideBeforeOff = defaults.bool(forKey: Key.dockAutoHideBeforeOff.rawValue)
        dockOffAgainAtLaunch = defaults.bool(forKey: Key.dockOffAgainAtLaunch.rawValue)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon.rawValue)
        hasDonated = defaults.bool(forKey: Key.hasDonated.rawValue)
    }

    /// Puts every shortcut back to its default.
    func resetShortcuts() {
        shortcuts = ShortcutAction.defaultShortcuts
    }

    // MARK: - Export and import

    /// Everything that can move to another Mac. Left out: the Dock on or off state, which
    /// belongs to this Mac, and app identifiers that only last until the app quits ("pid:123").
    func snapshot() -> SettingsSnapshot {
        func lasting(_ ids: [String]) -> [String] { ids.filter { !$0.hasPrefix("pid:") } }
        return SettingsSnapshot(
            windowManagerEnabled: windowManagerEnabled,
            maximizeEnabled: maximizeEnabled,
            greenButtonEnabled: greenButtonEnabled,
            snappingEnabled: snappingEnabled,
            windowShortcutsEnabled: windowShortcutsEnabled,
            shortcuts: Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) }),
            finderEnabled: finderEnabled,
            desktopEnabled: desktopEnabled,
            desktopSortOrder: desktopSortOrder.rawValue,
            taskbarEnabled: taskbarEnabled,
            taskbarDisplayMode: taskbarDisplayMode.rawValue,
            taskbarAppScope: taskbarAppScope.rawValue,
            taskbarShowAppNames: taskbarShowAppNames,
            taskbarReserveSpace: taskbarReserveSpace,
            taskbarPosition: taskbarPosition.rawValue,
            taskbarIconPoints: taskbarIconPoints,
            taskbarNamePosition: taskbarNamePosition.rawValue,
            taskbarGlassBackground: taskbarGlassBackground,
            taskbarCornerStyle: taskbarCornerStyle.rawValue,
            taskbarNameSize: taskbarNameSize.rawValue,
            taskbarShowTrash: taskbarShowTrash,
            taskbarPinnedApps: lasting(taskbarPinnedApps),
            taskbarAppOrder: lasting(taskbarAppOrder),
            taskbarGroupingEnabled: taskbarGroupingEnabled,
            taskbarAutoGroupNewApps: taskbarAutoGroupNewApps,
            taskbarGroups: taskbarGroups.map { TaskbarGroup(id: $0.id, name: $0.name, appIDs: lasting($0.appIDs)) },
            taskbarHiddenApps: lasting(taskbarHiddenApps),
            taskbarHiddenIcon: taskbarHiddenIcon.rawValue,
            taskbarDisplayRules: taskbarDisplayRules,
            showMenuBarIcon: showMenuBarIcon,
            hasDonated: hasDonated
        )
    }

    /// Takes over every setting the snapshot has. A setting the snapshot does not have, or has
    /// with a value this version does not know, stays as it is. The rest of the app hears about
    /// it once, at the end, so nothing reacts to a half-applied setup.
    func apply(_ snapshot: SettingsSnapshot) {
        batch {
            if let value = snapshot.windowManagerEnabled { windowManagerEnabled = value }
            if let value = snapshot.maximizeEnabled { maximizeEnabled = value }
            if let value = snapshot.greenButtonEnabled { greenButtonEnabled = value }
            if let value = snapshot.snappingEnabled { snappingEnabled = value }
            if let value = snapshot.windowShortcutsEnabled { windowShortcutsEnabled = value }
            if let saved = snapshot.shortcuts {
                var result: [ShortcutAction: KeyCombo] = [:]
                for (rawAction, combo) in saved {
                    if let action = ShortcutAction(rawValue: rawAction) { result[action] = combo }
                }
                shortcuts = result
            }
            if let value = snapshot.finderEnabled { finderEnabled = value }
            if let value = snapshot.desktopEnabled { desktopEnabled = value }
            if let value = snapshot.desktopSortOrder.flatMap(DesktopSortOrder.init(rawValue:)) { desktopSortOrder = value }

            if let value = snapshot.taskbarDisplayMode.flatMap(TaskbarDisplayMode.init(rawValue:)) { taskbarDisplayMode = value }
            if let value = snapshot.taskbarAppScope.flatMap(TaskbarAppScope.init(rawValue:)) { taskbarAppScope = value }
            if let value = snapshot.taskbarShowAppNames { taskbarShowAppNames = value }
            if let value = snapshot.taskbarReserveSpace { taskbarReserveSpace = value }
            if let value = snapshot.taskbarPosition.flatMap(TaskbarPosition.init(rawValue:)) { taskbarPosition = value }
            if let value = snapshot.taskbarIconPoints { taskbarIconPoints = TaskbarIconScale.clamped(value) }
            if let value = snapshot.taskbarNamePosition.flatMap(TaskbarNamePosition.init(rawValue:)) { taskbarNamePosition = value }
            if let value = snapshot.taskbarGlassBackground { taskbarGlassBackground = value }
            if let value = snapshot.taskbarCornerStyle.flatMap(TaskbarCornerStyle.init(rawValue:)) { taskbarCornerStyle = value }
            if let value = snapshot.taskbarNameSize.flatMap(TaskbarNameSize.init(rawValue:)) { taskbarNameSize = value }
            if let value = snapshot.taskbarShowTrash { taskbarShowTrash = value }
            if let value = snapshot.taskbarPinnedApps { taskbarPinnedApps = value }
            if let value = snapshot.taskbarAppOrder { taskbarAppOrder = value }
            if let value = snapshot.taskbarGroups { taskbarGroups = value }
            if let value = snapshot.taskbarGroupingEnabled { taskbarGroupingEnabled = value }
            if let value = snapshot.taskbarAutoGroupNewApps { taskbarAutoGroupNewApps = value }
            if let value = snapshot.taskbarHiddenApps { taskbarHiddenApps = value }
            if let value = snapshot.taskbarHiddenIcon.flatMap(HiddenAppsIcon.init(rawValue:)) { taskbarHiddenIcon = value }
            if let value = snapshot.taskbarDisplayRules { taskbarDisplayRules = value }
            if let value = snapshot.taskbarEnabled { taskbarEnabled = value }

            if let value = snapshot.showMenuBarIcon { showMenuBarIcon = value }
            if let value = snapshot.hasDonated { hasDonated = value }
        }
    }

    /// Runs several changes and tells the rest of the app once, after the last one.
    private func batch(_ changes: () -> Void) {
        isBatching = true
        changes()
        isBatching = false
        announceChange()
    }

    // MARK: - Storage

    private func announceChange() {
        guard !isBatching else { return }
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        announceChange()
    }

    private func storeShortcuts() {
        let encodable = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Key.shortcuts.rawValue)
        }
        announceChange()
    }

    private func storeGroups() {
        if let data = try? JSONEncoder().encode(taskbarGroups) {
            defaults.set(data, forKey: Key.taskbarGroups.rawValue)
        }
        announceChange()
    }

    private func storeDisplayRules() {
        if let data = try? JSONEncoder().encode(taskbarDisplayRules) {
            defaults.set(data, forKey: Key.taskbarDisplayRules.rawValue)
        }
        announceChange()
    }

    private static func loadDisplayRules(from defaults: UserDefaults) -> [TaskbarDisplayRule] {
        guard let data = defaults.data(forKey: Key.taskbarDisplayRules.rawValue) else { return [] }
        return (try? JSONDecoder().decode([TaskbarDisplayRule].self, from: data)) ?? []
    }

    private static func loadGroups(from defaults: UserDefaults) -> [TaskbarGroup] {
        guard let data = defaults.data(forKey: Key.taskbarGroups.rawValue) else { return [] }
        return (try? JSONDecoder().decode([TaskbarGroup].self, from: data)) ?? []
    }

    private static func loadShortcuts(from defaults: UserDefaults) -> [ShortcutAction: KeyCombo] {
        guard let data = defaults.data(forKey: Key.shortcuts.rawValue),
              let decoded = try? JSONDecoder().decode([String: KeyCombo].self, from: data)
        else {
            return ShortcutAction.defaultShortcuts
        }
        var result: [ShortcutAction: KeyCombo] = [:]
        for (rawAction, combo) in decoded {
            if let action = ShortcutAction(rawValue: rawAction) {
                result[action] = combo
            }
        }
        return result
    }
}
