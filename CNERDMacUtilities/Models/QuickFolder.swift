import Foundation

/// A folder shortcut shown in Finder Enhancements.
struct QuickFolder: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let url: URL

    /// The built-in folders. Custom folders are planned for a later version.
    static var standard: [QuickFolder] {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        func folder(_ directory: FileManager.SearchPathDirectory, fallback: String) -> URL {
            files.urls(for: directory, in: .userDomainMask).first ?? home.appendingPathComponent(fallback)
        }
        return [
            QuickFolder(id: "home", title: "Home", symbolName: "house", url: home),
            QuickFolder(id: "documents", title: "Documents", symbolName: "doc", url: folder(.documentDirectory, fallback: "Documents")),
            QuickFolder(id: "downloads", title: "Downloads", symbolName: "arrow.down.circle", url: folder(.downloadsDirectory, fallback: "Downloads")),
            QuickFolder(id: "desktop", title: "Desktop", symbolName: "menubar.dock.rectangle", url: folder(.desktopDirectory, fallback: "Desktop")),
            QuickFolder(id: "applications", title: "Applications", symbolName: "square.grid.3x3", url: URL(fileURLWithPath: "/Applications", isDirectory: true)),
        ]
    }
}
