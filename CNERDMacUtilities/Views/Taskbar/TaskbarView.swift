import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The contents of one taskbar: an Applications button, the apps, and the Trash.
/// Lays out left to right on the top and bottom edges, and top to bottom on the left and right edges.
struct TaskbarView: View {
    let controller: TaskbarController

    private var settings: AppSettings { controller.settings }
    private var position: TaskbarPosition { settings.taskbarPosition }
    private var isHorizontal: Bool { position.isHorizontal }
    private var isRounded: Bool { settings.taskbarCornerStyle == .rounded }
    private var iconSize: CGFloat { settings.taskbarIconSize.points }
    /// On a side bar with names beside the icons, everything lines up on the left.
    private var alignsLeading: Bool {
        !isHorizontal && settings.taskbarShowAppNames && settings.taskbarNamePosition.isBeside
    }

    var body: some View {
        let outer = isHorizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(alignment: alignsLeading ? .leading : .center, spacing: 8))

        outer {
            applicationsButton
            separator
            appList
            if settings.taskbarShowTrash {
                separator
                trashButton
            }
        }
        .padding(isHorizontal ? .horizontal : .vertical, 10)
        .padding(isHorizontal ? .vertical : .horizontal, TaskbarLayout.barMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
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
        .help("Open the Applications folder")
        .accessibilityLabel("Applications")
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
        .help("Open the Trash")
        .accessibilityLabel("Trash")
    }

    @ViewBuilder
    private var separator: some View {
        if isHorizontal {
            Divider().frame(height: 22)
        } else {
            Divider().frame(width: 22)
        }
    }

    private var appList: some View {
        let inner = isHorizontal
            ? AnyLayout(HStackLayout(spacing: 4))
            : AnyLayout(VStackLayout(alignment: alignsLeading ? .leading : .center, spacing: 4))

        return ScrollView(isHorizontal ? .horizontal : .vertical, showsIndicators: false) {
            inner {
                ForEach(controller.apps) { app in
                    TaskbarAppCell(
                        app: app,
                        iconSize: iconSize,
                        showName: settings.taskbarShowAppNames,
                        namePosition: settings.taskbarNamePosition,
                        nameSize: settings.taskbarNameSize.points,
                        isHorizontalBar: isHorizontal,
                        controller: controller
                    )
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

/// One app on the taskbar. Click to open or switch, drag to reorder, right-click for the menu.
private struct TaskbarAppCell: View {
    let app: TaskbarApp
    let iconSize: CGFloat
    let showName: Bool
    let namePosition: TaskbarNamePosition
    let nameSize: CGFloat
    let isHorizontalBar: Bool
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
                        .fill(app.isActive ? Color.accentColor : Color.secondary.opacity(0.7))
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
                controller.draggedAppID = app.id
                return NSItemProvider(object: app.id as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: TaskbarReorderDelegate(
                    targetID: app.id,
                    isHorizontal: isHorizontalBar,
                    length: isHorizontalBar ? cellSize.width : cellSize.height,
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
            .contextMenu {
                menu
            }
    }

    /// Mirrors the Dock's right-click menu.
    @ViewBuilder
    private var menu: some View {
        if app.isRunning {
            Button("Show All Windows") { controller.showAllWindows(of: app) }
            Button("Hide") { controller.hide(app) }
        } else {
            Button("Open") { controller.activate(app) }
        }

        Divider()

        if app.canBePinned {
            if app.isRunning {
                Toggle("Keep in Taskbar", isOn: Binding(
                    get: { app.isPinned },
                    set: { controller.setPinned($0, app: app) }
                ))
            } else {
                Button("Remove from Taskbar") { controller.setPinned(false, app: app) }
            }
        }
        if app.bundleURL != nil {
            Button("Show in Finder") { controller.showInFinder(app) }
        }

        if app.isRunning {
            Divider()
            Button("Quit") { controller.quit(app) }
        }
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
            .frame(width: TaskbarLayout.stackedCellWidth(iconSize: iconSize, nameSize: nameSize) - 2 * TaskbarLayout.buttonPadding)
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
            _ = controller.placeDraggedApp(before: offset < length / 2, targetID: targetID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        controller.draggedAppID = nil
        return true
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
