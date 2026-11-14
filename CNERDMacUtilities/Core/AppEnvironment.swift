import AppKit
import Observation

/// Selected sidebar destination, shared so the Dashboard can jump to a module.
@MainActor
@Observable
final class AppNavigation {
    var selection: SidebarItem? = .dashboard

    /// Reopens the main window after it was closed. Set by the main window the first time it shows.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    /// Brings the main window forward on one screen. Used by the taskbar, which lives outside the window.
    func show(_ item: SidebarItem) {
        selection = item
        openMainWindow?()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == WindowID.main }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}

/// Creates and owns every service and module. Views get this through the SwiftUI environment.
/// To add a module: create its controller here and add it to `modules`.
@MainActor
@Observable
final class AppEnvironment {
    let settings: AppSettings
    let navigation: AppNavigation
    let permissions: PermissionsService
    let loginItem: LoginItemService

    let windowManager: WindowManagerController
    let finder: FinderController
    let desktop: DesktopController
    let taskbar: TaskbarController

    /// The one environment of the running app. The app delegate uses it to build the Dock icon's menu.
    @ObservationIgnored static weak var current: AppEnvironment?

    init() {
        let settings = AppSettings()
        let permissions = PermissionsService()
        self.settings = settings
        let navigation = AppNavigation()
        self.navigation = navigation
        self.permissions = permissions
        self.loginItem = LoginItemService()
        self.windowManager = WindowManagerController(settings: settings, permissions: permissions)
        self.finder = FinderController(settings: settings, permissions: permissions)
        self.desktop = DesktopController(settings: settings)
        let taskbar = TaskbarController(settings: settings)
        self.taskbar = taskbar
        // Window Manager keeps maximized and snapped windows clear of the taskbar.
        windowManager.screenInsets = { screen in taskbar.reservedInsets(for: screen) }
        // Right-clicking the taskbar's Applications button opens its settings.
        taskbar.showSettings = { item in navigation.show(item) }
        Self.current = self
    }

    /// Dashboard status for a module, or nil if the item is not a module.
    func status(for item: SidebarItem) -> ModuleStatus? {
        modules.first { $0.sidebarItem == item }?.status
    }

    /// The utility modules in display order.
    var modules: [any UtilityModule] {
        [windowManager, finder, desktop, taskbar]
    }
}
