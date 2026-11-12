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
        case taskbarEnabled = "taskbar.enabled"
        case taskbarDisplayMode = "taskbar.displayMode"
        case taskbarShowAppNames = "taskbar.showAppNames"
        case taskbarReserveSpace = "taskbar.reserveSpace"
        case taskbarPosition = "taskbar.position"
        case taskbarIconSize = "taskbar.iconSize"
        case taskbarNamePosition = "taskbar.namePosition"
        case taskbarGlassBackground = "taskbar.glassBackground"
        case taskbarCornerStyle = "taskbar.cornerStyle"
        case taskbarNameSize = "taskbar.nameSize"
        case taskbarShowTrash = "taskbar.showTrash"
        case taskbarPinnedApps = "taskbar.pinnedApps"
        case taskbarAppOrder = "taskbar.appOrder"
        case dockAutoHideBeforeOff = "dock.autoHideBeforeOff"
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
    var taskbarShowAppNames: Bool { didSet { store(taskbarShowAppNames, .taskbarShowAppNames) } }
    /// Which edge of each display the taskbar uses. Independent of the macOS Dock.
    var taskbarPosition: TaskbarPosition { didSet { store(taskbarPosition.rawValue, .taskbarPosition) } }
    var taskbarIconSize: TaskbarIconSize { didSet { store(taskbarIconSize.rawValue, .taskbarIconSize) } }
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
    /// What the Dock's auto-hide setting was before the Dock was turned off, so it can be put back.
    var dockAutoHideBeforeOff: Bool { didSet { store(dockAutoHideBeforeOff, .dockAutoHideBeforeOff) } }
    /// When on, Window Manager keeps maximized and snapped windows clear of the taskbar.
    var taskbarReserveSpace: Bool { didSet { store(taskbarReserveSpace, .taskbarReserveSpace) } }

    // General
    var showMenuBarIcon: Bool { didSet { store(showMenuBarIcon, .showMenuBarIcon) } }

    private let defaults: UserDefaults

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
            Key.taskbarShowAppNames.rawValue: true,
            Key.taskbarReserveSpace.rawValue: true,
            Key.taskbarPosition.rawValue: TaskbarPosition.bottom.rawValue,
            Key.taskbarIconSize.rawValue: TaskbarIconSize.medium.rawValue,
            Key.taskbarNamePosition.rawValue: TaskbarNamePosition.right.rawValue,
            Key.taskbarGlassBackground.rawValue: true,
            Key.taskbarCornerStyle.rawValue: TaskbarCornerStyle.square.rawValue,
            Key.taskbarNameSize.rawValue: TaskbarNameSize.small.rawValue,
            Key.taskbarShowTrash.rawValue: true,
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
        taskbarShowAppNames = defaults.bool(forKey: Key.taskbarShowAppNames.rawValue)
        taskbarReserveSpace = defaults.bool(forKey: Key.taskbarReserveSpace.rawValue)
        taskbarPosition = TaskbarPosition(rawValue: defaults.string(forKey: Key.taskbarPosition.rawValue) ?? "") ?? .bottom
        taskbarIconSize = TaskbarIconSize(rawValue: defaults.string(forKey: Key.taskbarIconSize.rawValue) ?? "") ?? .medium
        taskbarNamePosition = TaskbarNamePosition(rawValue: defaults.string(forKey: Key.taskbarNamePosition.rawValue) ?? "") ?? .right
        taskbarGlassBackground = defaults.bool(forKey: Key.taskbarGlassBackground.rawValue)
        taskbarCornerStyle = TaskbarCornerStyle(rawValue: defaults.string(forKey: Key.taskbarCornerStyle.rawValue) ?? "") ?? .square
        taskbarNameSize = TaskbarNameSize(rawValue: defaults.string(forKey: Key.taskbarNameSize.rawValue) ?? "") ?? .small
        taskbarShowTrash = defaults.bool(forKey: Key.taskbarShowTrash.rawValue)
        taskbarPinnedApps = defaults.stringArray(forKey: Key.taskbarPinnedApps.rawValue) ?? []
        taskbarAppOrder = defaults.stringArray(forKey: Key.taskbarAppOrder.rawValue) ?? []
        dockAutoHideBeforeOff = defaults.bool(forKey: Key.dockAutoHideBeforeOff.rawValue)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon.rawValue)
    }

    /// Puts every shortcut back to its default.
    func resetShortcuts() {
        shortcuts = ShortcutAction.defaultShortcuts
    }

    // MARK: - Storage

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }

    private func storeShortcuts() {
        let encodable = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Key.shortcuts.rawValue)
        }
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
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
