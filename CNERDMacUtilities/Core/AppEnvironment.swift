import Foundation
import Observation

/// Selected sidebar destination, shared so the Dashboard can jump to a module.
@MainActor
@Observable
final class AppNavigation {
    var selection: SidebarItem? = .dashboard
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

    init() {
        let settings = AppSettings()
        let permissions = PermissionsService()
        self.settings = settings
        self.navigation = AppNavigation()
        self.permissions = permissions
        self.loginItem = LoginItemService()
        self.windowManager = WindowManagerController(settings: settings, permissions: permissions)
        self.finder = FinderController(settings: settings, permissions: permissions)
        self.desktop = DesktopController(settings: settings)
        let taskbar = TaskbarController(settings: settings)
        self.taskbar = taskbar
        // Window Manager keeps maximized and snapped windows clear of the taskbar.
        windowManager.screenInsets = { screen in taskbar.reservedInsets(for: screen) }
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
