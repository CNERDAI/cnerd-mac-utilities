import Foundation

/// How the Desktop file list is ordered. This only affects the list in the app,
/// never the icon arrangement on the real desktop.
enum DesktopSortOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    case kind
    case dateModified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .kind: "Type"
        case .dateModified: "Date Modified"
        }
    }
}

/// One file or folder on the Desktop. Read-only.
struct DesktopItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let kind: String
    let modified: Date?
    let isDirectory: Bool

    var id: URL { url }

    /// Reads the visible items in a folder. Does not change anything on disk.
    static func load(from directory: URL) throws -> [DesktopItem] {
        let keys: [URLResourceKey] = [.localizedNameKey, .localizedTypeDescriptionKey, .contentModificationDateKey, .isDirectoryKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return DesktopItem(
                url: url,
                name: values?.localizedName ?? url.lastPathComponent,
                kind: values?.localizedTypeDescription ?? "Unknown",
                modified: values?.contentModificationDate,
                isDirectory: values?.isDirectory ?? false
            )
        }
    }

    static func sorted(_ items: [DesktopItem], by order: DesktopSortOrder) -> [DesktopItem] {
        func byName(_ a: DesktopItem, _ b: DesktopItem) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch order {
        case .name:
            return items.sorted(by: byName)
        case .kind:
            return items.sorted { a, b in
                let result = a.kind.localizedStandardCompare(b.kind)
                return result == .orderedSame ? byName(a, b) : result == .orderedAscending
            }
        case .dateModified:
            // Newest first. Items without a date go last.
            return items.sorted { a, b in
                switch (a.modified, b.modified) {
                case let (x?, y?): return x == y ? byName(a, b) : x > y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return byName(a, b)
                }
            }
        }
    }
}
