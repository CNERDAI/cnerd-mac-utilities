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

/// Which taskbars an app shows on when more than one display has a taskbar.
enum TaskbarAppScope: String, CaseIterable, Identifiable, Sendable {
    /// Every taskbar shows every app.
    case allTaskbars
    /// The main taskbar shows every app. The others show the apps with a window on their display.
    case mainAndWindowDisplay
    /// Each taskbar shows only the apps with a window on its display.
    case windowDisplayOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTaskbars: "All Taskbars"
        case .mainAndWindowDisplay: "Main Taskbar and Where the Window Is"
        case .windowDisplayOnly: "Only Where the Window Is"
        }
    }

    /// The taskbars one app shows on.
    ///
    /// `windowDisplays` are the displays the app has a window on, or had one on when it last
    /// showed a window. `bars` are the displays with a taskbar, the main taskbar first.
    /// An app with no known window, or with windows only on displays that have no taskbar,
    /// goes to the main taskbar, so every app is always reachable from some taskbar.
    func bars(forAppOn windowDisplays: Set<UInt32>, bars: [UInt32]) -> Set<UInt32> {
        guard self != .allTaskbars, bars.count > 1, let main = bars.first else { return Set(bars) }
        var result = windowDisplays.intersection(bars)
        if result.isEmpty || self == .mainAndWindowDisplay { result.insert(main) }
        return result
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

/// One run of apps on the taskbar: a group, or the whole list when grouping is off.
struct TaskbarSection: Identifiable, Equatable {
    /// The single section used while grouping is off.
    static let allAppsID = "section.all"
    /// Apps that cannot be grouped because they have no bundle identifier.
    static let ungroupedID = "section.ungrouped"
    /// Apps tucked behind the Hidden Apps button.
    static let hiddenID = "section.hidden"

    let id: String
    let name: String
    let apps: [TaskbarApp]
    /// True for a group the user can rename, move, and delete.
    let isGroup: Bool
}

/// What one taskbar draws after its apps are fitted to the bar's length.
struct TaskbarBarContent {
    /// The apps on the bar, in sections.
    let sections: [TaskbarSection]
    /// Apps that did not fit. They sit behind the More button.
    let overflow: [TaskbarApp]
    /// Icon size on this bar. Never larger than the size chosen in the settings.
    let iconSize: CGFloat
    let showNames: Bool
    /// False on a display that shows only its chosen apps, without the Applications, Hidden Apps,
    /// and Trash buttons.
    var showsButtons = true
    /// True on a display that shows only its chosen apps. Dragging then reorders that display's own list.
    var isChosenApps = false
}

/// The pop-ups a taskbar can open.
enum TaskbarPopup: Equatable, Sendable {
    /// Apps the person tucked behind the Hidden Apps button. The same on every taskbar.
    case hiddenApps
    /// Apps that did not fit on one display's taskbar.
    case moreApps(display: UInt32)
}

/// Which bar is in use: this app's taskbar, or the macOS Dock.
enum BarMode: String, CaseIterable, Identifiable, Sendable {
    case taskbar
    case appleDock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taskbar: "Taskbar"
        case .appleDock: "Apple Dock"
        }
    }

    /// The menu command that changes to the other bar.
    var switchTitle: String {
        switch self {
        case .taskbar: "Switch to Apple Dock"
        case .appleDock: "Switch to Taskbar"
        }
    }
}

/// The picture on the Hidden Apps button.
enum HiddenAppsIcon: String, CaseIterable, Identifiable, Sendable {
    case sunglasses
    case stack
    case eye
    case drawer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunglasses: "Sunglasses"
        case .stack: "Stack"
        case .eye: "Eye"
        case .drawer: "Drawer"
        }
    }

    var symbolName: String {
        switch self {
        case .sunglasses: "sunglasses.fill"
        case .stack: "square.stack.3d.up.fill"
        case .eye: "eye.slash.fill"
        case .drawer: "tray.full.fill"
        }
    }
}

/// A disk the Trash menu can eject.
struct EjectableVolume: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String

    var id: URL { url }
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

    /// Places an app next to another one in the hidden list. An app that was not hidden yet joins the list.
    static func placingHidden(_ id: String, before: Bool, target: String, in hidden: [String]) -> [String] {
        guard !id.hasPrefix("pid:"), hidden.contains(target) else { return hidden }
        return placing(id, before: before, target: target, in: hidden.contains(id) ? hidden : hidden + [id])
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

/// The size of app icons on the taskbar, in points. Set with a slider.
enum TaskbarIconScale {
    static let range: ClosedRange<Double> = 16...72
    static let defaultPoints: Double = 26

    /// Whole points, kept inside the slider's range.
    static func clamped(_ points: Double) -> Double {
        min(max(points.rounded(), range.lowerBound), range.upperBound)
    }

    /// Version 1.0 stored "small", "medium", or "large". Those map to the sizes they had then.
    static func points(forLegacySize name: String?) -> Double {
        switch name {
        case "small": 20
        case "large": 34
        default: defaultPoints
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
    /// Space before the first button and after the last one, along the bar.
    static let barEndPadding: CGFloat = 10
    /// Space between the parts of the bar: Applications, the apps, More, Hidden Apps, Trash.
    static let partSpacing: CGFloat = 8
    /// Space between two apps.
    static let appSpacing: CGFloat = 4
    /// Thickness of the line between parts and between groups.
    static let separatorThickness: CGFloat = 1

    /// The More button's length along the bar. It shows a count such as "+31", so on a top or
    /// bottom bar it stays wide enough to read even when the icons are at their smallest.
    static func moreButtonLength(iconSize: CGFloat, isHorizontal: Bool) -> CGFloat {
        let side = iconSize + 2 * buttonPadding
        return isHorizontal ? max(side, 40) : side
    }
    /// How much of an app icon's canvas the artwork fills. Apple's icon grid puts an 824 point
    /// body on a 1024 point canvas, and the rest is empty margin.
    static let iconBodyFraction: CGFloat = 824.0 / 1024.0

    /// Where the body of a standard app icon sits inside its canvas: centered, with the margin
    /// Apple's icon grid leaves. Artwork that has no margin of its own is drawn here so it comes
    /// out the same size as the icons macOS supplies.
    static func iconBodyRect(in canvas: CGRect) -> CGRect {
        let inset = (1 - iconBodyFraction) / 2
        return canvas.insetBy(dx: canvas.width * inset, dy: canvas.height * inset)
    }

    /// Gap between the taskbar and a right-click menu that opens beside it.
    static let menuGap: CGFloat = 4

    /// Where the top left corner of a right-click menu goes so the menu sits beside the taskbar
    /// and not on top of it. Screen coordinates, with y growing upward. `click` is the pointer,
    /// `bar` is the taskbar's frame.
    static func menuTopLeft(click: CGPoint, bar: CGRect, menuSize: CGSize, position: TaskbarPosition) -> CGPoint {
        switch position {
        case .bottom: CGPoint(x: click.x, y: bar.maxY + menuGap + menuSize.height)
        case .top: CGPoint(x: click.x, y: bar.minY - menuGap)
        case .left: CGPoint(x: bar.maxX + menuGap, y: click.y)
        case .right: CGPoint(x: bar.minX - menuGap - menuSize.width, y: click.y)
        }
    }

    // MARK: Dragging the bar to another edge

    /// How far the pointer has to move, with the button held down on an empty part of the bar,
    /// before it counts as a drag. A plain click never moves the bar.
    static let barDragThreshold: CGFloat = 8
    /// How much closer the pointer has to be to another edge before the bar's target changes,
    /// as a share of the display. Keeps the target from flickering along a diagonal.
    static let barDragHysteresis: CGFloat = 0.04

    /// The edge a dragged taskbar lands on: the edge of its display the pointer is closest to.
    ///
    /// Distances are a share of the display's width and height, which cuts the display along its
    /// diagonals, the way the Windows taskbar chooses an edge. AppKit coordinates (y grows upward).
    /// A pointer outside the display counts as being on the display's nearest edge. The target
    /// stays on `current` until another edge is closer by more than `barDragHysteresis`.
    static func dragEdge(for point: CGPoint, in screen: CGRect, current: TaskbarPosition) -> TaskbarPosition {
        guard screen.width > 0, screen.height > 0 else { return current }
        let x = min(max((point.x - screen.minX) / screen.width, 0), 1)
        let y = min(max((point.y - screen.minY) / screen.height, 0), 1)
        let distances: [(edge: TaskbarPosition, distance: CGFloat)] = [
            (.bottom, y), (.top, 1 - y), (.left, x), (.right, 1 - x),
        ]
        var best = current
        var bestDistance = (distances.first { $0.edge == current }?.distance ?? 1) - barDragHysteresis
        for (edge, distance) in distances where edge != current && distance < bestDistance {
            best = edge
            bestDistance = distance
        }
        return best
    }

    /// How far outside the bar the pointer has to go before the bar can land on another edge.
    static let barDragHomeMargin: CGFloat = 12

    /// The edge a dragged taskbar lands on, given where the bar is now. While the pointer is on
    /// the bar itself, or within `barDragHomeMargin` of it, the bar stays on its own edge (`home`),
    /// so a drag along the bar never moves it, not even at a corner of the screen. Past that,
    /// `dragEdge` decides.
    static func dragTarget(
        for point: CGPoint, bar: CGRect, home: TaskbarPosition, screen: CGRect, current: TaskbarPosition
    ) -> TaskbarPosition {
        if bar.insetBy(dx: -barDragHomeMargin, dy: -barDragHomeMargin).contains(point) { return home }
        return dragEdge(for: point, in: screen, current: current)
    }

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

    // MARK: Hidden Apps pop-up

    static let hiddenPopupPadding: CGFloat = 8
    static let hiddenPopupSpacing: CGFloat = 4
    /// Space between the pop-up and the taskbar, and between the pop-up and the screen edges.
    static let hiddenPopupGap: CGFloat = 6
    static let hiddenPopupNameSize: CGFloat = 10
    static let hiddenPopupMaxColumns = 5

    static func hiddenPopupColumns(count: Int) -> Int {
        max(1, min(count, hiddenPopupMaxColumns))
    }

    /// One app in the pop-up: the icon with its name underneath. Wider than a cell on the bar,
    /// so most app names fit without being cut short.
    static func hiddenPopupCellSize(iconSize: CGFloat) -> CGSize {
        CGSize(
            width: max(stackedCellWidth(iconSize: iconSize, nameSize: hiddenPopupNameSize), 92),
            height: iconSize + stackedNameHeight(nameSize: hiddenPopupNameSize) + stackedSpacing + 2 * buttonPadding
        )
    }

    /// The pop-up is a grid, up to five apps wide. The view uses the same numbers.
    static func hiddenPopupSize(count: Int, iconSize: CGFloat) -> CGSize {
        let columns = hiddenPopupColumns(count: count)
        let rows = max(1, (max(count, 1) + columns - 1) / columns)
        let cell = hiddenPopupCellSize(iconSize: iconSize)
        return CGSize(
            width: CGFloat(columns) * cell.width + CGFloat(columns - 1) * hiddenPopupSpacing + 2 * hiddenPopupPadding,
            height: CGFloat(rows) * cell.height + CGFloat(rows - 1) * hiddenPopupSpacing + 2 * hiddenPopupPadding
        )
    }

    /// Where the pop-up goes, in AppKit coordinates: next to the taskbar on the side facing the
    /// screen, centered on the Hidden Apps button, and never off the screen.
    static func hiddenPopupFrame(size: CGSize, anchor: CGRect, bar: CGRect, screen: CGRect, position: TaskbarPosition) -> CGRect {
        let gap = hiddenPopupGap
        var origin: CGPoint
        switch position {
        case .bottom: origin = CGPoint(x: anchor.midX - size.width / 2, y: bar.maxY + gap)
        case .top: origin = CGPoint(x: anchor.midX - size.width / 2, y: bar.minY - gap - size.height)
        case .left: origin = CGPoint(x: bar.maxX + gap, y: anchor.midY - size.height / 2)
        case .right: origin = CGPoint(x: bar.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        origin.x = max(min(origin.x, screen.maxX - size.width - gap), screen.minX + gap)
        origin.y = max(min(origin.y, screen.maxY - size.height - gap), screen.minY + gap)
        return CGRect(origin: origin, size: size)
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

/// How one taskbar shows its apps once they are fitted to the bar's length.
struct TaskbarFit: Equatable, Sendable {
    var iconSize: CGFloat
    var showNames: Bool
    /// How many apps stay on the bar, counted from the start. The rest go behind the More button.
    var visibleCount: Int
}

/// What a taskbar has to fit. Lengths run along the bar: width on the top and bottom edges,
/// height on the left and right edges.
struct TaskbarFitRequest: Sendable {
    var barLength: CGFloat
    var isHorizontal: Bool
    /// The icon size chosen in the settings.
    var iconSize: CGFloat
    var showNames: Bool
    var namePosition: TaskbarNamePosition
    var nameSize: CGFloat
    /// How many apps each section has, in bar order.
    var sectionCounts: [Int]
    /// The drawn width of each app's name, in bar order. Only needed on a top or bottom bar
    /// with names beside the icons. A missing width counts as the widest a name can be.
    var nameWidths: [CGFloat] = []
    var showsHiddenButton = false
    var showsTrash = false
    /// Off on a display that shows only its chosen apps, without the other buttons.
    var showsApplicationsButton = true
}

/// Pure rules for a taskbar with more apps than it has room for.
///
/// The steps, in order, stopping as soon as everything fits:
/// 1. Hide the app names.
/// 2. Make the icons smaller, down to `minimumIconSize`.
/// 3. Move the apps at the end behind a More button.
///
/// The bar keeps the thickness from the settings. Only what is drawn on it changes, so every
/// display's taskbar stays the same thickness and windows keep the same free area.
enum TaskbarFitting {
    /// Icons never get smaller than the low end of the icon size slider.
    static let minimumIconSize = CGFloat(TaskbarIconScale.range.lowerBound)
    /// Room kept free so rounding never pushes the last app off the bar.
    static let slack: CGFloat = 1

    static func fit(_ request: TaskbarFitRequest) -> TaskbarFit {
        let count = request.sectionCounts.reduce(0, +)
        let limit = request.barLength - slack
        func fits(_ iconSize: CGFloat, _ showNames: Bool) -> Bool {
            length(request, iconSize: iconSize, showNames: showNames, visibleCount: count, showsMore: false) <= limit
        }

        if fits(request.iconSize, request.showNames) {
            return TaskbarFit(iconSize: request.iconSize, showNames: request.showNames, visibleCount: count)
        }

        // On a side bar, names beside the icons widen the bar but do not lengthen it.
        // Hiding them would free no room, so they stay.
        let namesTakeLength = request.isHorizontal || !request.namePosition.isBeside
        let showNames = request.showNames && !namesTakeLength
        if showNames != request.showNames, fits(request.iconSize, showNames) {
            return TaskbarFit(iconSize: request.iconSize, showNames: showNames, visibleCount: count)
        }

        var iconSize = request.iconSize.rounded(.up) - 1
        while iconSize >= minimumIconSize {
            if fits(iconSize, showNames) {
                return TaskbarFit(iconSize: iconSize, showNames: showNames, visibleCount: count)
            }
            iconSize -= 1
        }

        // Still too long with the smallest icons: keep as many apps as fit next to a More button.
        let smallest = min(request.iconSize, minimumIconSize)
        var visible = count - 1
        while visible > 0 {
            if length(request, iconSize: smallest, showNames: showNames, visibleCount: visible, showsMore: true) <= limit { break }
            visible -= 1
        }
        return TaskbarFit(iconSize: smallest, showNames: showNames, visibleCount: max(visible, 0))
    }

    /// The length of everything on the bar, laid out the way `TaskbarView` draws it:
    /// Applications, a line, the apps, More, then Hidden Apps and the Trash with a line before each.
    static func length(
        _ request: TaskbarFitRequest, iconSize: CGFloat, showNames: Bool, visibleCount: Int, showsMore: Bool
    ) -> CGFloat {
        let button = iconSize + 2 * TaskbarLayout.buttonPadding
        let line = 2 * TaskbarLayout.partSpacing + TaskbarLayout.separatorThickness
        var total = 2 * TaskbarLayout.barEndPadding
        if request.showsApplicationsButton { total += button + line }
        total += appsLength(request, iconSize: iconSize, showNames: showNames, visibleCount: visibleCount)
        if showsMore {
            total += TaskbarLayout.partSpacing
                + TaskbarLayout.moreButtonLength(iconSize: iconSize, isHorizontal: request.isHorizontal)
        }
        if request.showsHiddenButton { total += line + button }
        if request.showsTrash { total += line + button }
        return total
    }

    /// The length of the first `visibleCount` apps, with the lines between their sections.
    static func appsLength(_ request: TaskbarFitRequest, iconSize: CGFloat, showNames: Bool, visibleCount: Int) -> CGFloat {
        var remaining = visibleCount
        var index = 0
        var sections = 0
        var total: CGFloat = 0
        for count in request.sectionCounts where remaining > 0 {
            let shown = min(count, remaining)
            guard shown > 0 else { continue }
            sections += 1
            for _ in 0..<shown {
                let nameWidth = index < request.nameWidths.count ? request.nameWidths[index] : .greatestFiniteMagnitude
                total += cellLength(request, iconSize: iconSize, showNames: showNames, nameWidth: nameWidth)
                index += 1
            }
            remaining -= shown
        }
        guard index > 0 else { return 0 }
        let gaps = index + sections - 2
        return total + CGFloat(sections - 1) * TaskbarLayout.separatorThickness + CGFloat(gaps) * TaskbarLayout.appSpacing
    }

    /// The length of one app along the bar.
    static func cellLength(_ request: TaskbarFitRequest, iconSize: CGFloat, showNames: Bool, nameWidth: CGFloat) -> CGFloat {
        let padded = iconSize + 2 * TaskbarLayout.buttonPadding
        guard showNames else { return padded }
        let nameSize = request.nameSize
        switch (request.isHorizontal, request.namePosition.isBeside) {
        case (true, true):
            let name = min(nameWidth, TaskbarLayout.besideNameWidth(nameSize: nameSize))
            return iconSize + TaskbarLayout.iconNameSpacing + name + 2 * TaskbarLayout.besideHorizontalPadding
        case (true, false):
            return TaskbarLayout.stackedCellWidth(iconSize: iconSize, nameSize: nameSize)
        case (false, true):
            return max(iconSize, nameLineHeight(nameSize: nameSize)) + 2 * TaskbarLayout.buttonPadding
        case (false, false):
            return padded + TaskbarLayout.stackedNameHeight(nameSize: nameSize) + TaskbarLayout.stackedSpacing
        }
    }

    /// The height of one line of name text. A little generous, so a row is never cut short.
    static func nameLineHeight(nameSize: CGFloat) -> CGFloat {
        (nameSize * 1.3).rounded(.up)
    }
}
