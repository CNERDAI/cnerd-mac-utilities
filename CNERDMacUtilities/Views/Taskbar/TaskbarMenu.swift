import AppKit
import SwiftUI

/// One line of a right-click menu on the taskbar.
enum TaskbarMenuItem {
    case button(String, action: @MainActor () -> Void)
    /// A line with a small picture in front, such as a folder. `symbol` is an SF Symbol name.
    case item(String, symbol: String, action: @MainActor () -> Void)
    /// A line with a check mark. The action gets the new state.
    case toggle(String, isOn: Bool, action: @MainActor (Bool) -> Void)
    case submenu(String, [TaskbarMenuItem])
    /// A gray line that cannot be chosen. It only says something.
    case note(String)
    case divider
}

/// Turns menu items into an AppKit menu.
///
/// The taskbar shows its right-click menus itself, with `NSMenu.popUp(positioning:at:in:)`, and
/// does not use SwiftUI's `contextMenu`. On a display that sits above the main display, macOS
/// (measured on 27.2.1) moves a context menu off the screen about a tenth of a second after it
/// opens, so the menu flashes and is gone. That happens with SwiftUI's `contextMenu`, with
/// `NSMenu.popUpContextMenu`, and with `NSView.menu(for:)`. `popUp(positioning:at:in:)` stays put.
/// See docs/FEASIBILITY.md.
@MainActor
enum TaskbarMenuBuilder {
    static func menu(_ items: [TaskbarMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item {
            case .button(let title, let action):
                menu.addItem(ClosureMenuItem(title: title, handler: action))
            case .item(let title, let symbol, let action):
                let line = ClosureMenuItem(title: title, handler: action)
                line.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                menu.addItem(line)
            case .toggle(let title, let isOn, let action):
                let line = ClosureMenuItem(title: title) { action(!isOn) }
                line.state = isOn ? .on : .off
                menu.addItem(line)
            case .submenu(let title, let children):
                let submenu = Self.menu(children)
                guard submenu.numberOfItems > 0 else { continue }
                let line = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                line.submenu = submenu
                menu.addItem(line)
            case .note(let title):
                let line = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                line.isEnabled = false
                menu.addItem(line)
            case .divider:
                // No divider at the top, and never two in a row.
                if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
            }
        }
        // No divider at the bottom either.
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
        return menu
    }
}

/// A menu line that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Not used")
    }

    /// Menu actions are always sent on the main thread.
    @MainActor @objc private func run() {
        handler()
    }
}

/// Where the right-click menus of one taskbar window are. Each part of the bar that has a menu
/// reports its frame here, measured by SwiftUI in the window's own coordinate space (origin at
/// the top left, y growing downward). `TaskbarPanel` looks a right-click up in this list.
@MainActor
@Observable
final class TaskbarMenuRegistry {
    struct Region {
        var frame: CGRect
        /// The edge the taskbar is on, so the menu opens beside the bar. Nil inside a pop-up,
        /// where the menu opens at the pointer.
        var edge: TaskbarPosition?
        /// True for the bar itself, the region behind every button and app. A point that is on
        /// the bar and on nothing smaller is on the empty part of the bar.
        var isBar = false
        var items: @MainActor () -> [TaskbarMenuItem]
    }

    /// The name of the coordinate space the frames are measured in. `TaskbarPanel` sets it on its root view.
    static let space = "taskbarPanel"

    @ObservationIgnored private var regions: [UUID: Region] = [:]

    func set(
        _ id: UUID, frame: CGRect, edge: TaskbarPosition?, isBar: Bool = false,
        items: @escaping @MainActor () -> [TaskbarMenuItem]
    ) {
        regions[id] = Region(frame: frame, edge: edge, isBar: isBar, items: items)
    }

    /// Keeps the menu of a region current when its view is drawn again without moving.
    func refresh(
        _ id: UUID, edge: TaskbarPosition?, isBar: Bool = false,
        items: @escaping @MainActor () -> [TaskbarMenuItem]
    ) {
        guard let frame = regions[id]?.frame else { return }
        regions[id] = Region(frame: frame, edge: edge, isBar: isBar, items: items)
    }

    func remove(_ id: UUID) {
        regions[id] = nil
    }

    /// The regions under a point, smallest first: an app before the bar it sits on.
    func regions(at point: CGPoint) -> [Region] {
        regions.values
            .filter { $0.frame.contains(point) }
            .sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// True when the point is on the bar and on nothing smaller: not on a button and not on an app.
    /// That part of the bar can be dragged to move the taskbar to another edge.
    func isEmptyBar(at point: CGPoint) -> Bool {
        regions(at: point).first?.isBar == true
    }
}

/// Reports where a view is to the taskbar window's `TaskbarMenuRegistry`, with its menu.
private struct TaskbarMenuModifier: ViewModifier {
    let edge: TaskbarPosition?
    let isBar: Bool
    let items: @MainActor () -> [TaskbarMenuItem]

    @Environment(TaskbarMenuRegistry.self) private var registry: TaskbarMenuRegistry?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(TaskbarMenuRegistry.space))
                // The view may be drawn again with new values and the same frame.
                let _ = registry?.refresh(id, edge: edge, isBar: isBar, items: items)
                Color.clear
                    .onAppear { registry?.set(id, frame: frame, edge: edge, isBar: isBar, items: items) }
                    .onChange(of: frame) { _, newFrame in
                        registry?.set(id, frame: newFrame, edge: edge, isBar: isBar, items: items)
                    }
                    .onDisappear { registry?.remove(id) }
            }
        }
    }
}

extension View {
    /// Gives this part of a taskbar a right-click menu. Put it last, so it covers the whole view.
    /// The items are worked out when the menu opens. `isBar` marks the bar itself, whose empty
    /// part can also be dragged to another edge of the screen.
    func taskbarMenu(
        edge: TaskbarPosition?, isBar: Bool = false, items: @escaping @MainActor () -> [TaskbarMenuItem]
    ) -> some View {
        modifier(TaskbarMenuModifier(edge: edge, isBar: isBar, items: items))
    }
}
