import SwiftUI

/// Every destination in the main window sidebar.
/// To add a utility module: add a case here, a controller in Modules/, and a screen in Views/Settings/.
enum SidebarItem: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case windowManager
    case finderEnhancements
    case desktopManager
    case taskbar
    case generalSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .windowManager: "Window Manager"
        case .finderEnhancements: "Finder Enhancements"
        case .desktopManager: "Desktop Manager"
        case .taskbar: "Taskbar & Dock"
        case .generalSettings: "General Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .windowManager: "macwindow.on.rectangle"
        case .finderEnhancements: "folder.fill"
        case .desktopManager: "desktopcomputer"
        case .taskbar: "dock.rectangle"
        case .generalSettings: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: .indigo
        case .windowManager: .blue
        case .finderEnhancements: .teal
        case .desktopManager: .orange
        case .taskbar: .purple
        case .generalSettings: .gray
        }
    }

    var summary: String {
        switch self {
        case .dashboard: "An overview of your utilities."
        case .windowManager: "Maximize, restore, and snap windows the way Windows does."
        case .finderEnhancements: "Hidden files, path copying, and quick folder access."
        case .desktopManager: "Desktop files and display information."
        case .taskbar: "A Windows-style taskbar on the displays you choose, plus switches for the macOS Dock."
        case .generalSettings: "Startup, permissions, and application information."
        }
    }

    /// The utility modules, in display order.
    static let modules: [SidebarItem] = [.windowManager, .finderEnhancements, .desktopManager, .taskbar]
}
