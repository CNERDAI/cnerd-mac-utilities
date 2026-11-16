import Foundation

/// A folder shortcut. Shown in Finder Enhancements and in Finder's right-click menu on the taskbar.
struct QuickFolder: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let url: URL
    /// True for a folder the person added. Those can be removed. The built-in ones cannot.
    var isCustom = false

    /// The built-in folders.
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

    /// A folder the person added, from its path as the settings keep it ("~/Projects").
    /// The folder itself is not looked at, so listing it never needs a permission.
    static func custom(storedPath: String, home: String = NSHomeDirectory()) -> QuickFolder {
        let path = QuickFolders.fullPath(storedPath, home: home)
        let name = (path as NSString).lastPathComponent
        return QuickFolder(
            id: "custom:\(storedPath)",
            title: name.isEmpty || name == "/" ? path : name,
            symbolName: "folder",
            url: URL(fileURLWithPath: path, isDirectory: true),
            isCustom: true
        )
    }
}

/// Pure rules for the list of folders the person added.
///
/// Paths inside the home folder are kept with a leading "~", so a settings file made on one Mac
/// still points at the right folders on a Mac with another user name.
enum QuickFolders {
    /// The path as the settings keep it: tidied, with "~" in place of the home folder.
    static func storedPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        var tidy = (path as NSString).standardizingPath
        while tidy.count > 1, tidy.hasSuffix("/") { tidy.removeLast() }
        let home = (home as NSString).standardizingPath
        if tidy == home { return "~" }
        if tidy.hasPrefix(home + "/") { return "~" + tidy.dropFirst(home.count) }
        return tidy
    }

    /// The real path for a path the settings keep.
    static func fullPath(_ stored: String, home: String = NSHomeDirectory()) -> String {
        if stored == "~" { return home }
        if stored.hasPrefix("~/") { return home + stored.dropFirst(1) }
        return stored
    }

    /// Adds folders to the end of the list. A folder that is already there, or that is one of
    /// the built-in folders, is not added twice.
    static func adding(_ paths: [String], to stored: [String], builtIn: [String], home: String = NSHomeDirectory()) -> [String] {
        var result = stored
        let skip = Set(builtIn.map { storedPath($0, home: home) })
        for path in paths {
            let entry = storedPath(path, home: home)
            if !entry.isEmpty, !skip.contains(entry), !result.contains(entry) { result.append(entry) }
        }
        return result
    }

    static func removing(_ storedPath: String, from stored: [String]) -> [String] {
        stored.filter { $0 != storedPath }
    }
}
