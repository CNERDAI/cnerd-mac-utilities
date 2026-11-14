import AppKit
import SwiftUI

/// One line of a right-click menu on the taskbar.
enum TaskbarMenuItem {
    case button(String, action: @MainActor () -> Void)
    /// A line with a check mark. The action gets the new state.
    case toggle(String, isOn: Bool, action: @MainActor (Bool) -> Void)
    case submenu(String, [TaskbarMenuItem])
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

/// Marks the part of a taskbar that a right-click menu belongs to. It draws nothing and takes no
/// clicks. `TaskbarPanel` looks these up when a right-click arrives.
final class TaskbarMenuRegionView: NSView {
    var items: (@MainActor () -> [TaskbarMenuItem])?
    /// The edge the taskbar is on, so the menu opens beside the bar. Nil inside a pop-up, where
    /// the menu opens at the pointer.
    var edge: TaskbarPosition?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct TaskbarMenuRegion: NSViewRepresentable {
    let edge: TaskbarPosition?
    let items: @MainActor () -> [TaskbarMenuItem]

    func makeNSView(context: Context) -> TaskbarMenuRegionView {
        let view = TaskbarMenuRegionView()
        view.edge = edge
        view.items = items
        return view
    }

    func updateNSView(_ view: TaskbarMenuRegionView, context: Context) {
        view.edge = edge
        view.items = items
    }
}

extension View {
    /// Gives this part of a taskbar a right-click menu. Put it last, so it covers the whole view.
    /// The items are worked out when the menu opens.
    func taskbarMenu(edge: TaskbarPosition?, items: @escaping @MainActor () -> [TaskbarMenuItem]) -> some View {
        background { TaskbarMenuRegion(edge: edge, items: items) }
    }
}
