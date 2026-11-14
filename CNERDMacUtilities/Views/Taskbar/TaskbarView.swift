import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The taskbar of one display. It asks the controller which apps belong on this display and how
/// they fit the bar, then draws the result.
struct TaskbarView: View {
    let controller: TaskbarController
    /// The display this taskbar sits on.
    let displayID: UInt32

    var body: some View {
        TaskbarBar(controller: controller, displayID: displayID, content: controller.content(for: displayID))
    }
}

/// The contents of one taskbar: an Applications button, the apps (in groups when grouping is on),
/// the More button when apps did not fit, the Hidden Apps button, and the Trash.
/// Lays out left to right on the top and bottom edges, and top to bottom on the left and right edges.
private struct TaskbarBar: View {
    let controller: TaskbarController
    let displayID: UInt32
    /// The apps fitted to this bar. Icon size and names come from here, not straight from the
    /// settings, because a crowded bar shows smaller icons and hides names.
    let content: TaskbarBarContent

    private var settings: AppSettings { controller.settings }
    private var position: TaskbarPosition { settings.taskbarPosition }
    private var isHorizontal: Bool { position.isHorizontal }
    private var isRounded: Bool { settings.taskbarCornerStyle == .rounded }
    private var iconSize: CGFloat { content.iconSize }
    private var showNames: Bool { content.showNames }
    /// On a side bar with names beside the icons, everything lines up on the left.
    private var alignsLeading: Bool {
        !isHorizontal && showNames && settings.taskbarNamePosition.isBeside
    }

    var body: some View {
        let spacing = TaskbarLayout.partSpacing
        let outer = isHorizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(alignment: alignsLeading ? .leading : .center, spacing: spacing))

        outer {
            // A display that shows only its chosen apps can leave out the other buttons.
            if content.showsButtons {
                applicationsButton
                separator
            }
            appList
            if !content.overflow.isEmpty {
                MoreAppsButton(
                    controller: controller, displayID: displayID, apps: content.overflow,
                    iconSize: iconSize, isHorizontalBar: isHorizontal
                )
            }
            if content.showsButtons, !controller.hiddenApps.isEmpty {
                separator
                HiddenAppsButton(controller: controller, iconSize: iconSize)
            }
            if content.showsButtons, settings.taskbarShowTrash {
                separator
                trashButton
            }
        }
        .padding(isHorizontal ? .horizontal : .vertical, TaskbarLayout.barEndPadding)
        .padding(isHorizontal ? .vertical : .horizontal, TaskbarLayout.barMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        .contentShape(Rectangle())
        // An app dropped on the empty part of a chosen-apps taskbar joins that display's apps.
        .onDrop(
            of: content.isChosenApps ? [UTType.text] : [],
            delegate: ChosenDisplayDropDelegate(displayID: displayID, controller: controller)
        )
        // On a bar without its Applications button, a right-click on an empty part of the bar
        // opens the settings, so they stay within reach. Other bars get no menu there.
        .taskbarMenu(edge: position) {
            guard !content.showsButtons else { return [] }
            return [
                .button("App Icon Controls…") { controller.openSettings(.appIcons) },
                .button("Taskbar & Dock Settings…") { controller.openSettings(.taskbar) },
            ]
        }
        .background { background }
        .overlay { border }
    }

    // MARK: - Pieces

    private var applicationsButton: some View {
        let side = iconSize + 2 * TaskbarLayout.buttonPadding
        return Button {
            controller.openApplicationsFolder()
        } label: {
            Image(systemName: AppSymbol.applications)
                .font(.system(size: iconSize * 0.58, weight: .medium))
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to open the Applications folder. Right-click for settings and to switch to the Apple Dock.")
        .accessibilityLabel("Applications")
        .taskbarMenu(edge: position) {
            [
                .button("Taskbar & Dock Settings…") { controller.openSettings(.taskbar) },
                .button("App Icon Controls…") { controller.openSettings(.appIcons) },
                .divider,
                // Hides the taskbar and brings the Dock back. The way back is in the menu bar icon's
                // menu, the menu of this app's Dock icon, and the settings window.
                .button(BarMode.taskbar.switchTitle) { controller.switchBar(to: .appleDock) },
            ]
        }
    }

    private var trashButton: some View {
        let side = iconSize + 2 * TaskbarLayout.buttonPadding
        return Button {
            controller.openTrash()
        } label: {
            Group {
                if let image = NSImage(named: NSImage.trashEmptyName) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: iconSize * 0.58))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to open the Trash. Right-click to empty it or eject a disk.")
        .accessibilityLabel("Trash")
        .taskbarMenu(edge: position) {
            trashMenu
        }
    }

    /// Mirrors what the Dock's Trash offers: open, empty, and eject.
    private var trashMenu: [TaskbarMenuItem] {
        var items: [TaskbarMenuItem] = [
            .button("Open") { controller.openTrash() },
            .button("Empty Trash…") { controller.emptyTrash() },
        ]
        let volumes = controller.ejectableVolumes
        if !volumes.isEmpty {
            items.append(.divider)
            for volume in volumes {
                items.append(.button("Eject \(volume.name)") { controller.eject(volume) })
            }
            if volumes.count > 1 {
                items.append(.button("Eject All") { controller.ejectAll() })
            }
        }
        return items
    }

    /// The line between the parts of the bar, and between groups. It scales with the icons.
    @ViewBuilder
    private var separator: some View {
        let length = max(16, iconSize * 0.7)
        let thickness = TaskbarLayout.separatorThickness
        if isHorizontal {
            Divider().frame(width: thickness, height: length)
        } else {
            Divider().frame(width: length, height: thickness)
        }
    }

    private var appList: some View {
        let spacing = TaskbarLayout.appSpacing
        let inner = isHorizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(alignment: alignsLeading ? .leading : .center, spacing: spacing))

        // One section per group that has apps showing, or a single section when grouping is off.
        let sections = content.sections
        let groups = settings.taskbarGroupingEnabled ? settings.taskbarGroups : []

        // The apps are fitted to the bar, so there is normally nothing to scroll. The scroll view
        // stays as a safety net: if a name is drawn a point wider than measured, nothing is cut off.
        return ScrollView(isHorizontal ? .horizontal : .vertical, showsIndicators: false) {
            inner {
                ForEach(sections) { section in
                    if section.id != sections.first?.id {
                        separator
                    }
                    ForEach(section.apps) { app in
                        TaskbarAppCell(
                            app: app,
                            iconSize: iconSize,
                            showName: showNames,
                            namePosition: settings.taskbarNamePosition,
                            nameSize: settings.taskbarNameSize.points,
                            isHorizontalBar: isHorizontal,
                            groups: groups,
                            chosenDisplay: content.isChosenApps ? displayID : nil,
                            menuEdge: position,
                            controller: controller
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let radius = isRounded ? TaskbarLayout.roundedCornerRadius : 0
        if settings.taskbarGlassBackground {
            TaskbarGlassBackground(cornerRadius: radius)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// Rounded bars get a thin outline. Square bars get a hairline on the side facing the screen.
    @ViewBuilder
    private var border: some View {
        if isRounded {
            RoundedRectangle(cornerRadius: TaskbarLayout.roundedCornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                .allowsHitTesting(false)
        } else {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: isHorizontal ? nil : 1, height: isHorizontal ? 1 : nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: innerEdge)
                .allowsHitTesting(false)
        }
    }

    private var frameAlignment: Alignment {
        if isHorizontal { return .leading }
        return alignsLeading ? .topLeading : .top
    }

    private var innerEdge: Alignment {
        switch position {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }
}

/// One app on the taskbar or in the Hidden Apps pop-up. Click to open or switch, drag to reorder,
/// right-click for the menu.
private struct TaskbarAppCell: View {
    let app: TaskbarApp
    let iconSize: CGFloat
    let showName: Bool
    let namePosition: TaskbarNamePosition
    let nameSize: CGFloat
    let isHorizontalBar: Bool
    /// The groups an app can be moved to. Empty when grouping is off.
    let groups: [TaskbarGroup]
    /// A fixed width for a cell with the name above or below the icon. Nil uses the taskbar's own width.
    var stackedWidth: CGFloat?
    /// Set when the cell is on a display that shows only its chosen apps. Dragging then reorders
    /// that display's own list, and the menu can take the app off that display.
    var chosenDisplay: UInt32?
    /// The edge of the taskbar this cell is on, so its menu opens beside the bar. Nil in a pop-up.
    var menuEdge: TaskbarPosition?
    let controller: TaskbarController

    /// Measured size of this cell, used to tell which half the pointer is over during a drag.
    @State private var cellSize: CGSize = .zero

    private var namesBeside: Bool { showName && namePosition.isBeside }

    var body: some View {
        content
            .padding(.horizontal, namesBeside ? TaskbarLayout.besideHorizontalPadding : TaskbarLayout.buttonPadding)
            .padding(.vertical, TaskbarLayout.buttonPadding)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(app.isActive ? Color.primary.opacity(0.14) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                // Running marker, like the dot under a Dock icon. Wider and tinted for the app in front.
                if app.isRunning {
                    Capsule()
                        .fill(app.isActive ? Color.steadyAccent : Color.secondary.opacity(0.7))
                        .frame(width: app.isActive ? 16 : 5, height: 3)
                }
            }
            .opacity(app.isHidden ? 0.55 : 1)
            .contentShape(Rectangle())
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { cellSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in cellSize = newSize }
                }
            }
            .onTapGesture {
                controller.activate(app)
            }
            .onDrag {
                controller.beginAppDrag(app.id)
                return NSItemProvider(object: app.id as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: TaskbarReorderDelegate(
                    targetID: app.id,
                    isHorizontal: isHorizontalBar,
                    length: isHorizontalBar ? cellSize.width : cellSize.height,
                    chosenDisplay: chosenDisplay,
                    controller: controller
                )
            )
            .help(app.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(app.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                controller.activate(app)
            }
            .taskbarMenu(edge: menuEdge) {
                menu
            }
    }

    /// Mirrors the Dock's right-click menu.
    private var menu: [TaskbarMenuItem] {
        var items: [TaskbarMenuItem] = []
        if app.isRunning {
            items.append(.button("Show All Windows") { controller.showAllWindows(of: app) })
            items.append(.button("Hide") { controller.hide(app) })
        } else {
            items.append(.button("Open") { controller.activate(app) })
        }
        items.append(.divider)

        if app.canBePinned {
            if app.isRunning {
                items.append(.toggle("Keep in Taskbar", isOn: app.isPinned) { controller.setPinned($0, app: app) })
            } else if app.isPinned {
                items.append(.button("Remove from Taskbar") { controller.setPinned(false, app: app) })
            }
        }
        if let chosenDisplay, let display = controller.displays.first(where: { $0.id == chosenDisplay }) {
            items.append(.button("Remove from This Display") { controller.setChosen(false, appID: app.id, on: display) })
        }
        if app.canBePinned {
            // Displays set to Only Apps I Choose. A check mark means the app shows there.
            let displays = controller.chosenDisplays
            if !displays.isEmpty {
                items.append(.submenu("Show on Display", displays.map { display in
                    .toggle(display.name, isOn: controller.isChosen(app.id, on: display)) {
                        controller.setChosen($0, appID: app.id, on: display)
                    }
                }))
            }
            // Moves the app behind the Hidden Apps button, or brings it back. The app keeps running.
            if controller.isHiddenFromTaskbar(app.id) {
                items.append(.button("Show in Taskbar") { controller.setHiddenFromTaskbar(false, appID: app.id) })
            } else {
                items.append(.button("Hide from Taskbar") { controller.setHiddenFromTaskbar(true, appID: app.id) })
            }
            if !groups.isEmpty {
                items.append(.submenu("Move to Group", groups.map { group in
                    .button(group.name.isEmpty ? "Untitled Group" : group.name) {
                        controller.moveApp(app.id, toGroup: group.id)
                    }
                }))
            }
        }
        if app.bundleURL != nil {
            items.append(.button("Show in Finder") { controller.showInFinder(app) })
        }
        if app.isRunning {
            items.append(.divider)
            items.append(.button("Quit") { controller.quit(app) })
        }
        return items
    }

    @ViewBuilder
    private var content: some View {
        if !showName {
            icon
        } else if namePosition.isBeside {
            HStack(spacing: TaskbarLayout.iconNameSpacing) {
                if namePosition == .left { nameBeside }
                icon
                if namePosition == .right { nameBeside }
            }
        } else {
            VStack(spacing: TaskbarLayout.stackedSpacing) {
                if namePosition == .above { nameStacked }
                icon
                if namePosition == .below { nameStacked }
            }
            .frame(width: (stackedWidth ?? TaskbarLayout.stackedCellWidth(iconSize: iconSize, nameSize: nameSize)) - 2 * TaskbarLayout.buttonPadding)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = app.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: AppSymbol.applications)
                .frame(width: iconSize, height: iconSize)
        }
    }

    /// Name beside the icon. On a side bar every name gets the same width so the rows line up.
    private var nameBeside: some View {
        let width = TaskbarLayout.besideNameWidth(nameSize: nameSize)
        return Text(app.name)
            .font(.system(size: nameSize))
            .lineLimit(1)
            .frame(
                minWidth: isHorizontalBar ? nil : width,
                maxWidth: width,
                alignment: namePosition == .left ? .trailing : .leading
            )
    }

    /// Name above or below the icon, centered in a fixed-width cell.
    private var nameStacked: some View {
        Text(app.name)
            .font(.system(size: nameSize))
            .lineLimit(1)
            .frame(height: TaskbarLayout.stackedNameHeight(nameSize: nameSize))
    }
}

/// Reorders apps while one is dragged across the others. The dragged app goes before the app
/// under the pointer while the pointer is over its first half, and after it over its second half.
private struct TaskbarReorderDelegate: DropDelegate {
    let targetID: String
    let isHorizontal: Bool
    /// Length of the target cell along the bar.
    let length: CGFloat
    /// Set on a display that shows only its chosen apps. The drag then changes that display's list.
    var chosenDisplay: UInt32?
    let controller: TaskbarController

    func dropEntered(info: DropInfo) {
        place(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        place(info)
        return DropProposal(operation: .move)
    }

    private func place(_ info: DropInfo) {
        guard length > 0 else { return }
        let offset = isHorizontal ? info.location.x : info.location.y
        withAnimation(.easeInOut(duration: 0.15)) {
            if let chosenDisplay {
                // An app dragged in from another taskbar only joins once it is let go.
                if controller.isChosenDrag(onDisplayID: chosenDisplay) {
                    _ = controller.placeDraggedApp(before: offset < length / 2, targetID: targetID, onChosenDisplay: chosenDisplay)
                }
            } else {
                _ = controller.placeDraggedApp(before: offset < length / 2, targetID: targetID)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let chosenDisplay, length > 0, !controller.isChosenDrag(onDisplayID: chosenDisplay) {
            let offset = isHorizontal ? info.location.x : info.location.y
            _ = controller.placeDraggedApp(before: offset < length / 2, targetID: targetID, onChosenDisplay: chosenDisplay)
        }
        controller.endDrag()
        return true
    }
}

/// Handles a drop on the empty part of a taskbar that shows only its chosen apps: the dragged app
/// joins that display's apps. Nothing changes until the app is let go.
private struct ChosenDisplayDropDelegate: DropDelegate {
    let displayID: UInt32
    let controller: TaskbarController

    func validateDrop(info: DropInfo) -> Bool {
        controller.draggedAppID != nil && controller.showsChosenApps(on: displayID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        let added = controller.addDraggedApp(toChosenDisplay: displayID)
        controller.endDrag()
        return added
    }
}

/// The button at the end of the taskbar that holds the hidden apps. It shows how many of them are
/// running. Click it to open the pop-up, or drop an app on it to hide that app.
private struct HiddenAppsButton: View {
    let controller: TaskbarController
    let iconSize: CGFloat

    /// Knows where this button is on the screen, so the pop-up can open right next to it.
    @State private var anchor = ScreenAnchor()

    var body: some View {
        let side = iconSize + 2 * TaskbarLayout.buttonPadding
        let running = controller.runningHiddenCount

        Button {
            controller.togglePopup(.hiddenApps, anchor: anchor.screenFrame)
        } label: {
            Image(systemName: controller.hiddenIconSymbolName)
                .font(.system(size: iconSize * 0.58, weight: .medium))
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(controller.isHiddenAppsShown ? Color.primary.opacity(0.14) : Color.clear)
                )
                .overlay(alignment: .topTrailing) {
                    if running > 0 {
                        TaskbarCountBadge(count: running, iconSize: iconSize)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            ScreenAnchorReader(anchor: anchor)
                .allowsHitTesting(false)
        }
        .onDrop(of: [UTType.text], delegate: HideDropDelegate(controller: controller))
        .help("Hidden apps. Click to show them. Drop an app here to hide it.")
        .accessibilityLabel("Hidden apps")
        .accessibilityValue(running == 1 ? "1 running" : "\(running) running")
        .taskbarMenu(edge: controller.settings.taskbarPosition) {
            [
                .button(controller.isHiddenAppsShown ? "Close Hidden Apps" : "Show Hidden Apps") {
                    controller.togglePopup(.hiddenApps, anchor: anchor.screenFrame)
                },
                .button("Show All in Taskbar") { controller.showAllHiddenApps() },
                .divider,
                .button("App Icon Controls…") { controller.openSettings(.appIcons) },
            ]
        }
    }
}

/// A small number in the corner of a taskbar button.
private struct TaskbarCountBadge: View {
    let count: Int
    let iconSize: CGFloat

    var body: some View {
        let height = max(12, iconSize * 0.4)
        Text("\(count)")
            .font(.system(size: height * 0.72, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, height * 0.28)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(Color.steadyAccent))
            .offset(x: 2, y: -1)
            .accessibilityHidden(true)
    }
}

/// The button after the apps on a taskbar that is too short for all of them. It shows how many
/// apps did not fit, for example "+31". Click it to open them in a pop-up.
private struct MoreAppsButton: View {
    let controller: TaskbarController
    let displayID: UInt32
    /// The apps that did not fit on this taskbar.
    let apps: [TaskbarApp]
    let iconSize: CGFloat
    let isHorizontalBar: Bool

    /// Knows where this button is on the screen, so the pop-up can open right next to it.
    @State private var anchor = ScreenAnchor()

    private var popup: TaskbarPopup { .moreApps(display: displayID) }

    var body: some View {
        let side = iconSize + 2 * TaskbarLayout.buttonPadding
        let isOpen = controller.shownPopup == popup
        // The app in front may be one of the apps that did not fit. The button then carries its marker.
        let holdsActiveApp = apps.contains(where: \.isActive)

        Button {
            controller.togglePopup(popup, anchor: anchor.screenFrame)
        } label: {
            Text("+\(apps.count)")
                .font(.system(size: max(10, iconSize * 0.4), weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
                .frame(
                    width: isHorizontalBar ? TaskbarLayout.moreButtonLength(iconSize: iconSize, isHorizontal: true) : side,
                    height: isHorizontalBar ? side : TaskbarLayout.moreButtonLength(iconSize: iconSize, isHorizontal: false)
                )
                .background(
                    // Always lightly filled, so the number reads as a button. Darker when its
                    // pop-up is open or the app in front is behind it.
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isOpen || holdsActiveApp ? 0.18 : 0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            ScreenAnchorReader(anchor: anchor)
                .allowsHitTesting(false)
        }
        .help(apps.count == 1 ? "1 more app. Click to show it." : "\(apps.count) more apps. Click to show them.")
        .accessibilityLabel("More apps")
        .accessibilityValue(apps.count == 1 ? "1 app" : "\(apps.count) apps")
        .taskbarMenu(edge: controller.settings.taskbarPosition) {
            [
                .button(controller.shownPopup == popup ? "Close More Apps" : "Show More Apps") {
                    controller.togglePopup(popup, anchor: anchor.screenFrame)
                },
                .divider,
                .button("Taskbar & Dock Settings…") { controller.openSettings(.taskbar) },
            ]
        }
    }
}

/// Dropping a dragged app on the Hidden Apps button hides it.
private struct HideDropDelegate: DropDelegate {
    let controller: TaskbarController

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeInOut(duration: 0.15)) {
            _ = controller.setDraggedAppHidden(true)
        }
        controller.endDrag()
        return true
    }
}

/// Remembers the AppKit view behind a SwiftUI view, to find out where that view is on the screen.
@MainActor
final class ScreenAnchor {
    fileprivate weak var view: NSView?

    /// The view's frame in screen coordinates, or nil while it is not in a window.
    var screenFrame: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

private struct ScreenAnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// The pop-up that opens next to the Hidden Apps button or the More button. The apps in it behave
/// exactly like apps on the taskbar: click to switch, drag to reorder or back onto the taskbar,
/// right-click for the menu. Icons are the size chosen in the settings, with names underneath.
struct TaskbarPopupView: View {
    let controller: TaskbarController
    let popup: TaskbarPopup

    var body: some View {
        let settings = controller.settings
        let iconSize = CGFloat(settings.taskbarIconPoints)
        let apps = controller.apps(in: popup)
        // The More pop-up of a display with chosen apps reorders that display's own list.
        let chosenDisplay: UInt32? = if case .moreApps(let display) = popup, controller.showsChosenApps(on: display) {
            display
        } else {
            nil
        }
        let cell = TaskbarLayout.hiddenPopupCellSize(iconSize: iconSize)
        let columns = Array(
            repeating: GridItem(.fixed(cell.width), spacing: TaskbarLayout.hiddenPopupSpacing),
            count: TaskbarLayout.hiddenPopupColumns(count: apps.count)
        )
        let radius = TaskbarLayout.roundedCornerRadius

        LazyVGrid(columns: columns, spacing: TaskbarLayout.hiddenPopupSpacing) {
            ForEach(apps) { app in
                TaskbarAppCell(
                    app: app,
                    iconSize: iconSize,
                    showName: true,
                    namePosition: .below,
                    nameSize: TaskbarLayout.hiddenPopupNameSize,
                    isHorizontalBar: true,
                    groups: settings.taskbarGroupingEnabled ? settings.taskbarGroups : [],
                    stackedWidth: cell.width,
                    chosenDisplay: chosenDisplay,
                    controller: controller
                )
            }
        }
        .padding(TaskbarLayout.hiddenPopupPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if settings.taskbarGlassBackground {
                TaskbarGlassBackground(cornerRadius: radius)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// Native translucent glass background that follows light and dark mode.
private struct TaskbarGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.maskImage = Self.maskImage(cornerRadius: cornerRadius)
    }

    /// A stretchable rounded rectangle. The blur behind the window is only cut to shape through a mask image.
    private static func maskImage(cornerRadius: CGFloat) -> NSImage? {
        guard cornerRadius > 0 else { return nil }
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
