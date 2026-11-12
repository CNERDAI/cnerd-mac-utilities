import AppKit

/// Which displays show the CNERD taskbar.
enum TaskbarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case mainDisplayOnly
    case otherDisplaysOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allDisplays: "All Displays"
        case .mainDisplayOnly: "Main Display Only"
        case .otherDisplaysOnly: "Other Displays Only"
        }
    }

    /// Screen index 0 is the main display, the one with the menu bar.
    func includes(screenIndex: Int) -> Bool {
        switch self {
        case .allDisplays: true
        case .mainDisplayOnly: screenIndex == 0
        case .otherDisplaysOnly: screenIndex > 0
        }
    }
}

/// Where the macOS Dock sits. Raw values match both the Dock preference and the System Events term.
enum DockPosition: String, CaseIterable, Identifiable, Sendable {
    case left
    case bottom
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left"
        case .bottom: "Bottom"
        case .right: "Right"
        }
    }
}

/// One app shown on the taskbar: running, kept on the taskbar, or both.
struct TaskbarApp: Identifiable, Equatable {
    /// The bundle identifier, or "pid:123" for the rare app that has none.
    let id: String
    /// Nil when the app is kept on the taskbar but not running.
    let pid: pid_t?
    let name: String
    let bundleURL: URL?
    let icon: NSImage?
    let isActive: Bool
    let isHidden: Bool
    /// True when the user chose Keep in Taskbar.
    let isPinned: Bool

    var isRunning: Bool { pid != nil }
    /// Apps without a bundle identifier cannot be kept or reordered.
    var canBePinned: Bool { !id.hasPrefix("pid:") }

    static func == (lhs: TaskbarApp, rhs: TaskbarApp) -> Bool {
        lhs.id == rhs.id && lhs.pid == rhs.pid && lhs.name == rhs.name
            && lhs.isActive == rhs.isActive && lhs.isHidden == rhs.isHidden && lhs.isPinned == rhs.isPinned
    }
}

/// Pure rules for which apps show on the taskbar and in what order.
enum TaskbarOrdering {
    /// Adds apps that have not been seen before to the end of the saved order.
    static func merged(order: [String], adding ids: [String]) -> [String] {
        var result = order
        var seen = Set(order)
        for id in ids where !id.hasPrefix("pid:") && seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// Apps to show: everything kept or running, in the saved order, then running apps with no saved spot.
    static func visible(order: [String], pinned: Set<String>, running: [String]) -> [String] {
        let runningSet = Set(running)
        let ordered = Set(order)
        return order.filter { pinned.contains($0) || runningSet.contains($0) } + running.filter { !ordered.contains($0) }
    }

    /// Puts one app directly before or after another. Doing it twice gives the same result,
    /// so it is safe to call over and over while the pointer moves during a drag.
    static func placing(_ id: String, before: Bool, target: String, in order: [String]) -> [String] {
        guard id != target, order.contains(id), order.contains(target) else { return order }
        var result = order
        result.removeAll { $0 == id }
        guard let index = result.firstIndex(of: target) else { return order }
        result.insert(id, at: before ? index : index + 1)
        return result
    }
}

/// Which edge of a display the taskbar sits on.
enum TaskbarPosition: String, CaseIterable, Identifiable, Sendable {
    case bottom
    case top
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: "Bottom"
        case .top: "Top"
        case .left: "Left"
        case .right: "Right"
        }
    }

    /// True for the top and bottom edges, where apps run left to right.
    var isHorizontal: Bool { self == .bottom || self == .top }
}

enum TaskbarIconSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var points: CGFloat {
        switch self {
        case .small: 20
        case .medium: 26
        case .large: 34
        }
    }
}

/// Where an app's name sits relative to its icon.
enum TaskbarNamePosition: String, CaseIterable, Identifiable, Sendable {
    case right
    case left
    case above
    case below

    var id: String { rawValue }

    var title: String {
        switch self {
        case .right: "Right of Icon"
        case .left: "Left of Icon"
        case .above: "Above Icon"
        case .below: "Below Icon"
        }
    }

    /// True when the name is beside the icon, false when it is stacked above or below it.
    var isBeside: Bool { self == .right || self == .left }
}

/// How big app names are on the taskbar.
enum TaskbarNameSize: String, CaseIterable, Identifiable, Sendable {
    case extraSmall
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extraSmall: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var points: CGFloat {
        switch self {
        case .extraSmall: 9
        case .small: 10
        case .medium: 12
        case .large: 14
        }
    }
}

/// The shape of the taskbar.
enum TaskbarCornerStyle: String, CaseIterable, Identifiable, Sendable {
    /// Runs edge to edge with square corners, like the Windows taskbar.
    case square
    /// Floats slightly off the screen edge with rounded corners, like the macOS Dock.
    case rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: "Square Edges"
        case .rounded: "Rounded Edges"
        }
    }
}

/// Space kept free along the edges of a display, in points.
struct ScreenInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0

    static let zero = ScreenInsets()

    /// Shrinks a rectangle in AppKit coordinates (y grows upward). Never removes more than half of either side.
    func applied(toAppKitRect rect: CGRect) -> CGRect {
        let maxX = rect.width / 2
        let maxY = rect.height / 2
        let l = min(left, maxX), r = min(right, maxX), t = min(top, maxY), b = min(bottom, maxY)
        return CGRect(x: rect.minX + l, y: rect.minY + b, width: rect.width - l - r, height: rect.height - t - b)
    }
}

/// Pure sizing rules for the taskbar. The view uses the same numbers, so content always fits the bar.
enum TaskbarLayout {
    static let iconNameSpacing: CGFloat = 6
    static let stackedSpacing: CGFloat = 2
    /// Padding inside each app button, per side.
    static let buttonPadding: CGFloat = 4
    static let besideHorizontalPadding: CGFloat = 8
    /// Space between the buttons and the edges of the bar, per side.
    static let barMargin: CGFloat = 5
    /// Gap between a rounded taskbar and the screen edge.
    static let floatingMargin: CGFloat = 6
    static let roundedCornerRadius: CGFloat = 14

    /// Width given to a name that sits beside its icon. Scales with the text size.
    static func besideNameWidth(nameSize: CGFloat) -> CGFloat {
        nameSize * 10
    }

    /// Height of a name stacked above or below its icon.
    static func stackedNameHeight(nameSize: CGFloat) -> CGFloat {
        nameSize + 3
    }

    /// Width of one app cell when the name is stacked above or below the icon.
    static func stackedCellWidth(iconSize: CGFloat, nameSize: CGFloat) -> CGFloat {
        max(iconSize + 30, nameSize * 6.5)
    }

    /// The bar's height on the top or bottom edge, or its width on the left or right edge.
    static func thickness(
        position: TaskbarPosition,
        iconSize: CGFloat,
        showNames: Bool,
        namePosition: TaskbarNamePosition,
        nameSize: CGFloat = 12
    ) -> CGFloat {
        let margins = 2 * (buttonPadding + barMargin)
        if position.isHorizontal {
            let stacked = showNames && !namePosition.isBeside
            return iconSize + (stacked ? stackedNameHeight(nameSize: nameSize) + stackedSpacing : 0) + margins
        }
        guard showNames else { return iconSize + margins }
        if namePosition.isBeside {
            return iconSize + iconNameSpacing + besideNameWidth(nameSize: nameSize) + 2 * (besideHorizontalPadding + barMargin)
        }
        return stackedCellWidth(iconSize: iconSize, nameSize: nameSize) + margins
    }

    /// The bar's frame inside a display's usable area, in AppKit coordinates (y grows upward).
    /// A floating bar is pulled in from the screen edges by `floatingMargin` on every side.
    static func frame(in usable: CGRect, position: TaskbarPosition, thickness: CGFloat, floating: Bool = false) -> CGRect {
        let margin = floating ? floatingMargin : 0
        let band = thickness + 2 * margin
        let strip: CGRect
        switch position {
        case .bottom: strip = CGRect(x: usable.minX, y: usable.minY, width: usable.width, height: band)
        case .top: strip = CGRect(x: usable.minX, y: usable.maxY - band, width: usable.width, height: band)
        case .left: strip = CGRect(x: usable.minX, y: usable.minY, width: band, height: usable.height)
        case .right: strip = CGRect(x: usable.maxX - band, y: usable.minY, width: band, height: usable.height)
        }
        return strip.insetBy(dx: margin, dy: margin)
    }

    /// Space other windows should leave free for the bar.
    static func insets(position: TaskbarPosition, thickness: CGFloat, floating: Bool = false) -> ScreenInsets {
        let band = thickness + (floating ? 2 * floatingMargin : 0)
        switch position {
        case .bottom: return ScreenInsets(bottom: band)
        case .top: return ScreenInsets(top: band)
        case .left: return ScreenInsets(left: band)
        case .right: return ScreenInsets(right: band)
        }
    }
}
