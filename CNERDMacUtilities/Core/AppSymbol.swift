import Foundation

/// SF Symbol names used by views that are not tied to a model type.
/// Kept in one place so a unit test can confirm every name exists on this macOS version.
enum AppSymbol {
    static let menuBar = "macwindow.on.rectangle"
    static let warning = "exclamationmark.triangle.fill"
    static let checkmark = "checkmark.circle.fill"
    static let info = "info.circle"
    static let remove = "xmark.circle.fill"
    static let refresh = "arrow.clockwise"
    static let copy = "doc.on.doc"
    static let display = "display"
    static let folder = "folder"
    static let lock = "lock.shield"
    static let applications = "square.grid.3x3.fill"
    static let donate = "heart.fill"
    static let pinned = "pin.fill"
    static let unpinned = "pin"
    static let dragHandle = "line.3.horizontal"
    static let moveUp = "chevron.up"
    static let moveDown = "chevron.down"
    static let trash = "trash"
    static let trashFull = "trash.fill"
    static let add = "plus"

    static let all: [String] = [menuBar, warning, checkmark, info, remove, refresh, copy, display, folder, lock, applications, donate, pinned, unpinned, dragHandle, moveUp, moveDown, trash, trashFull, add]
}
