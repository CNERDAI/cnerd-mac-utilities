import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The utilities keep working after the settings window is closed.
    /// Quit from the menu bar icon, the Dock, or with Command-Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Adds the bar switch to the menu of the app's own Dock icon. While the Apple Dock is in use
    /// the taskbar is gone, so this is one of the ways to bring it back.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let taskbar = AppEnvironment.current?.taskbar else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: taskbar.barMode.switchTitle, action: #selector(switchBar), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @MainActor @objc private func switchBar() {
        AppEnvironment.current?.taskbar.toggleBar()
    }
}
