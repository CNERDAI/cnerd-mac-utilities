import AppKit
import SwiftUI

/// The borderless window that holds one taskbar. It floats above normal windows, never takes
/// keyboard focus, shows on every desktop Space, and stays out of Full Screen Spaces.
final class TaskbarPanel: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = FirstClickHostingView(rootView: AnyView(rootView))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Right-clicks (and Control-clicks) open the taskbar's own menus. Everything else goes on
    /// to SwiftUI as usual.
    override func sendEvent(_ event: NSEvent) {
        let isMenuClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if isMenuClick, showMenu(for: event) { return }
        super.sendEvent(event)
    }

    /// Opens the menu of the smallest marked region under the pointer: an app before the bar
    /// it sits on. Returns false when there is no menu there.
    private func showMenu(for event: NSEvent) -> Bool {
        guard let root = contentView else { return false }
        let point = event.locationInWindow
        var best: (region: TaskbarMenuRegionView, area: CGFloat)?
        func visit(_ view: NSView) {
            if let region = view as? TaskbarMenuRegionView, !region.isHiddenOrHasHiddenAncestor {
                let frame = region.convert(region.visibleRect, to: nil)
                let area = frame.width * frame.height
                if frame.contains(point), area < (best?.area ?? .greatestFiniteMagnitude) {
                    best = (region, area)
                }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        guard let region = best?.region, let items = region.items?(), !items.isEmpty else { return false }

        let menu = TaskbarMenuBuilder.menu(items)
        guard menu.numberOfItems > 0 else { return false }
        if let edge = region.edge {
            // Beside the bar, the way the Dock shows its menus, so the menu never covers the bar.
            let origin = TaskbarLayout.menuTopLeft(
                click: convertPoint(toScreen: point), bar: frame, menuSize: menu.size, position: edge
            )
            menu.popUp(positioning: nil, at: origin, in: nil)
        } else {
            menu.popUp(positioning: nil, at: root.convert(point, from: nil), in: root)
        }
        return true
    }
}

/// Lets taskbar buttons react to the first click even though the app is in the background.
private final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
