import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The utilities keep working after the settings window is closed.
    /// Quit from the menu bar icon, the Dock, or with Command-Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
