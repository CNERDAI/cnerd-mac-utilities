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
        contentView = FirstClickHostingView(rootView: AnyView(
            rootView
                .coordinateSpace(.named(TaskbarMenuRegistry.space))
                .environment(menuRegistry)
        ))
    }

    /// Where this window's right-click menus are. The views report their own frames.
    let menuRegistry = TaskbarMenuRegistry()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// What a drag of the empty part of the bar reports. Points are in screen coordinates.
    enum BarDragPhase: Equatable {
        /// The pointer moved with the button held down.
        case moved(NSPoint)
        /// The button was let go.
        case ended(NSPoint)
        /// The drag stopped without a place to land.
        case cancelled
    }

    /// Called while the empty part of this taskbar is dragged toward another edge of the screen.
    /// Set by the taskbar controller. A pop-up has none, so it cannot be dragged.
    var onBarDrag: (@MainActor (BarDragPhase) -> Void)?

    /// Where the button went down on the empty part of the bar, in screen coordinates.
    private var barDragStart: NSPoint?
    /// True once the pointer has moved far enough to count as a drag.
    private var isDraggingBar = false

    /// Right-clicks (and Control-clicks) open the taskbar's own menus. A press on the empty part
    /// of a taskbar starts a drag to another edge. Everything else goes on to SwiftUI as usual.
    override func sendEvent(_ event: NSEvent) {
        let isMenuClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if isMenuClick {
            // A right-click in the middle of a drag calls the drag off.
            cancelBarDrag()
            if showMenu(for: event) { return }
        } else if handleBarDrag(event) {
            return
        }
        super.sendEvent(event)
    }

    /// Follows the left mouse button on the empty part of the bar. Returns true when the event
    /// belongs to that press and must not go on to SwiftUI.
    ///
    /// Nothing on the empty part of the bar takes a click, so the whole press is kept here:
    /// SwiftUI never sees half of a click.
    private func handleBarDrag(_ event: NSEvent) -> Bool {
        guard onBarDrag != nil else { return false }
        switch event.type {
        case .leftMouseDown:
            // A press that never got its release (it should not happen) ends here.
            cancelBarDrag()
            guard let root = contentView else { return false }
            let point = event.locationInWindow
            let fromTop = CGPoint(x: point.x, y: root.bounds.height - point.y)
            guard menuRegistry.isEmptyBar(at: fromTop) else { return false }
            barDragStart = convertPoint(toScreen: point)
            return true
        case .leftMouseDragged:
            guard let start = barDragStart else { return false }
            let now = convertPoint(toScreen: event.locationInWindow)
            if !isDraggingBar {
                guard hypot(now.x - start.x, now.y - start.y) >= TaskbarLayout.barDragThreshold else { return true }
                isDraggingBar = true
            }
            onBarDrag?(.moved(now))
            return true
        case .leftMouseUp:
            guard barDragStart != nil else { return false }
            let wasDragging = isDraggingBar
            barDragStart = nil
            isDraggingBar = false
            if wasDragging { onBarDrag?(.ended(convertPoint(toScreen: event.locationInWindow))) }
            return true
        default:
            return false
        }
    }

    /// Stops a drag of the bar without moving the taskbar.
    func cancelBarDrag() {
        let wasDragging = isDraggingBar
        barDragStart = nil
        isDraggingBar = false
        if wasDragging { onBarDrag?(.cancelled) }
    }

    /// Opens the menu for a right-click. The smallest region under the pointer that has a menu
    /// wins: an app before the bar it sits on. Returns false when there is no menu there.
    private func showMenu(for event: NSEvent) -> Bool {
        guard let root = contentView else { return false }
        let point = event.locationInWindow
        // The regions are measured from the top left of the window, with y growing downward.
        let fromTop = CGPoint(x: point.x, y: root.bounds.height - point.y)
        var chosen: (region: TaskbarMenuRegistry.Region, items: [TaskbarMenuItem])?
        for region in menuRegistry.regions(at: fromTop) {
            let items = region.items()
            if !items.isEmpty {
                chosen = (region, items)
                break
            }
        }
        guard let (region, items) = chosen else { return false }

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

/// The outline that shows where a dragged taskbar will land. It never takes a click.
final class TaskbarDragPreview: NSPanel {
    init() {
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
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        let view = NSView()
        view.wantsLayer = true
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the outline at a frame in screen coordinates, in the accent color.
    func show(frame: NSRect, cornerRadius: CGFloat) {
        if let layer = contentView?.layer {
            let accent = NSColor.controlAccentColor
            layer.backgroundColor = accent.withAlphaComponent(0.28).cgColor
            layer.borderColor = accent.withAlphaComponent(0.9).cgColor
            layer.borderWidth = 2
            layer.cornerRadius = cornerRadius
        }
        if self.frame != frame { setFrame(frame, display: true) }
        if !isVisible { orderFrontRegardless() }
    }
}

/// Lets taskbar buttons react to the first click even though the app is in the background.
private final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
