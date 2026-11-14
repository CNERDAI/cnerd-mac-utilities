import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App Icon Controls: the size of the app icons, the groups they sit in, and their order.
/// Everything here changes the taskbar right away.
struct AppIconsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isConfirmingRegroup = false

    var body: some View {
        @Bindable var settings = environment.settings
        let taskbar = environment.taskbar

        SettingsPage(.appIcons) {
            Section {
                TaskbarIconSizeRow(settings: settings)
            } header: {
                Text("Size")
            }

            Section {
                SettingToggle(
                    title: "Group Apps",
                    description: "Keeps related apps side by side on the taskbar, with a line between groups.",
                    isOn: $settings.taskbarGroupingEnabled
                )

                SettingToggle(
                    title: "Sort New Apps Automatically",
                    description: "An app that shows up for the first time goes into the group that fits it, such as Browsers or AI Tools. Turn off to place new apps yourself. They wait in Other.",
                    isOn: $settings.taskbarAutoGroupNewApps
                )
                .disabled(!settings.taskbarGroupingEnabled)

                SettingRow("Group by Topic", description: "Sorts every app into topic groups again. This replaces the groups you made.") {
                    Button("Group by Topic…") { isConfirmingRegroup = true }
                }
                .disabled(!settings.taskbarGroupingEnabled)
            } header: {
                Text("Groups")
            }

            Section {
                Picker(selection: $settings.taskbarHiddenIcon) {
                    ForEach(HiddenAppsIcon.allCases) { icon in
                        Label(icon.title, systemImage: icon.symbolName).tag(icon)
                    }
                } label: {
                    SettingLabel(
                        title: "Hidden Apps Button",
                        description: "The picture on the button at the end of the taskbar that holds your hidden apps. The number on it counts the hidden apps that are running."
                    )
                }
            } header: {
                Text("Hidden Apps")
            } footer: {
                Text("To hide an app, right-click it on the taskbar and choose Hide from Taskbar, or drag it onto the Hidden Apps button. The app keeps running. Click the button to see the hidden apps in a small window next to the taskbar. The button only shows while there is a hidden app to show.")
            }

            if settings.taskbarEnabled {
                displaysSections(taskbar: taskbar)
                arrangement(taskbar: taskbar, grouping: settings.taskbarGroupingEnabled)
            } else {
                Section {
                    NoticeRow(text: "The taskbar is off, so there are no apps to arrange.", kind: .info)
                    Button("Open Taskbar & Dock") { environment.navigation.selection = .taskbar }
                } header: {
                    Text("Arrange")
                }
            }
        }
        .confirmationDialog("Sort all apps by topic?", isPresented: $isConfirmingRegroup) {
            Button("Group by Topic") { taskbar.regroupByTopic() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every app moves to the group for its topic. Groups you made and the order inside them are replaced. Apps you keep on the taskbar stay kept.")
        }
    }

    /// One section per display that shows a taskbar. Only shown with two or more, because a
    /// single taskbar has nothing to tell apart.
    @ViewBuilder
    private func displaysSections(taskbar: TaskbarController) -> some View {
        let displays = taskbar.displays
        if displays.count > 1 {
            ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                DisplayAppsSection(
                    display: display,
                    isFirst: index == 0,
                    isLast: index == displays.count - 1,
                    controller: taskbar
                )
            }
        }
    }

    @ViewBuilder
    private func arrangement(taskbar: TaskbarController, grouping: Bool) -> some View {
        let sections = taskbar.sections(includingEmpty: true)
        let groupCount = sections.filter(\.isGroup).count

        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            AppGroupSection(
                section: section,
                index: index,
                groupCount: groupCount,
                groups: grouping ? environment.settings.taskbarGroups : [],
                controller: taskbar
            )
        }

        if grouping {
            Section {
                Button {
                    taskbar.addGroup()
                } label: {
                    Label("New Group", systemImage: AppSymbol.add)
                }
            }
        }

        // Hidden apps come last, the same as their button on the taskbar.
        AppGroupSection(
            section: TaskbarSection(id: TaskbarSection.hiddenID, name: "Hidden", apps: taskbar.hiddenApps, isGroup: false),
            index: sections.count,
            groupCount: groupCount,
            groups: grouping ? environment.settings.taskbarGroups : [],
            controller: taskbar
        )

        Section {
        } footer: {
            Text(grouping
                ? "Drag an app to move it inside its group or into another group. Drag a group by its handle, or use the arrows, to change the order of the groups. Drag an app into Hidden to tuck it behind the Hidden Apps button, and drag it out to bring it back. Click the pin to keep an app on the taskbar when it is not running. The taskbar shows the same order."
                : "Drag an app to change its place. Drag an app into Hidden to tuck it behind the Hidden Apps button, and drag it out to bring it back. Click the pin to keep an app on the taskbar when it is not running. Turn on Group Apps to sort the apps into groups.")
        }
    }
}

/// The icon size slider. Shown here and in Taskbar & Dock.
struct TaskbarIconSizeRow: View {
    let settings: AppSettings

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { settings.taskbarIconPoints },
                        set: { newValue in
                            let points = TaskbarIconScale.clamped(newValue)
                            if points != settings.taskbarIconPoints { settings.taskbarIconPoints = points }
                        }
                    ),
                    in: TaskbarIconScale.range
                )
                .frame(width: 200)
                .accessibilityLabel("Icon size")

                Text("\(Int(settings.taskbarIconPoints)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        } label: {
            SettingLabel(title: "Icon Size", description: "Drag to make the app icons smaller or larger. The taskbar follows as you drag.")
        }
    }
}

/// One display's taskbar: whether it follows Show Apps On or shows only chosen apps, and which apps.
private struct DisplayAppsSection: View {
    let display: TaskbarDisplay
    let isFirst: Bool
    let isLast: Bool
    let controller: TaskbarController

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 6)]

    var body: some View {
        let rule = controller.rule(for: display.id)
        let mode = rule?.mode ?? .followScope
        let apps = controller.chosenApps(on: display.id)

        Section {
            Picker(selection: Binding(get: { mode }, set: { controller.setAppMode($0, for: display) })) {
                ForEach(TaskbarDisplayAppMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: AppSymbol.display)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    SettingLabel(
                        title: display.name,
                        description: display.isMain ? "Main display, \(display.sizeText)" : display.sizeText
                    )
                }
            }
            .accessibilityLabel("Apps on the \(display.name) taskbar")

            if mode == .chosenApps {
                Group {
                    if apps.isEmpty {
                        Text("No apps yet. Choose Add App, or drag an app here from the groups below.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                            ForEach(apps) { app in
                                ChosenAppTile(app: app, display: display, controller: controller)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onDrop(of: [UTType.text], delegate: DisplayCardDropDelegate(display: display, controller: controller))

                SettingRow("Add Apps", description: "Chosen apps show on this taskbar whether they are running or not. A click opens them.") {
                    Button("Add App…") { chooseApps() }
                }

                SettingToggle(
                    title: "Show Applications, Hidden Apps, and Trash",
                    description: "Turn off for a bar with only the chosen apps. Right-click an empty part of that bar to reach these settings.",
                    isOn: Binding(
                        get: { rule?.showsButtons ?? false },
                        set: { controller.setShowsButtons($0, for: display) }
                    )
                )
            }
        } header: {
            if isFirst { Text("Displays") }
        } footer: {
            if isLast {
                Text("Each display's taskbar can follow Show Apps On in Taskbar & Dock, or show only the apps you choose for it. To add an app, choose Add App, drag it from the groups below, or right-click it on any taskbar and choose Show on Display. Drag the chosen apps to change their order.")
            }
        }
    }

    /// Lets the person pick apps for this display's taskbar.
    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Add Apps to the \(display.name) Taskbar"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        controller.addChosenApps(at: panel.urls, to: display)
    }
}

/// One app chosen for a display. Drag it to change its place, click the x to take it off that display.
private struct ChosenAppTile: View {
    let app: TaskbarApp
    let display: TaskbarDisplay
    let controller: TaskbarController

    /// Measured width, used to tell which half the pointer is over during a drag.
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image = app.icon {
                    Image(nsImage: image).resizable()
                } else {
                    Image(systemName: AppSymbol.applications).font(.system(size: 24))
                }
            }
            .frame(width: 40, height: 40)
            Text(app.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(alignment: .topTrailing) {
            Button {
                controller.setChosen(false, appID: app.id, on: display)
            } label: {
                Image(systemName: AppSymbol.remove)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Take \(app.name) off this display's taskbar")
            .accessibilityLabel("Remove \(app.name) from \(display.name)")
        }
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
            }
        }
        .onDrag {
            controller.beginAppDrag(app.id)
            return NSItemProvider(object: app.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: ChosenTileDropDelegate(targetID: app.id, display: display, width: width, controller: controller)
        )
        .help(app.isRunning ? app.name : "\(app.name) (not running)")
        .contextMenu {
            Button("Remove from This Display") { controller.setChosen(false, appID: app.id, on: display) }
            if app.bundleURL != nil {
                Button("Show in Finder") { controller.showInFinder(app) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
    }
}

/// Reorders a display's chosen apps while one is dragged across the others. An app dragged in
/// from the groups joins the display's apps next to the app under the pointer.
private struct ChosenTileDropDelegate: DropDelegate {
    let targetID: String
    let display: TaskbarDisplay
    let width: CGFloat
    let controller: TaskbarController

    func validateDrop(info: DropInfo) -> Bool {
        controller.draggedAppID != nil
    }

    func dropEntered(info: DropInfo) {
        place(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        place(info)
        return DropProposal(operation: .move)
    }

    private func place(_ info: DropInfo) {
        guard width > 0, controller.isChosenDrag(on: display) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            _ = controller.placeDraggedApp(before: info.location.x < width / 2, targetID: targetID, onChosenDisplay: display.id)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        // An app from the groups is only added once it is let go, next to the app it was dropped on.
        if !controller.isChosenDrag(on: display) {
            _ = controller.placeDraggedApp(before: info.location.x < width / 2, targetID: targetID, onChosenDisplay: display.id)
        }
        controller.endDrag()
        return true
    }
}

/// Handles a drop on the empty part of a display's card: the dragged app joins that display's
/// apps. Nothing changes until the app is let go.
private struct DisplayCardDropDelegate: DropDelegate {
    let display: TaskbarDisplay
    let controller: TaskbarController

    func validateDrop(info: DropInfo) -> Bool {
        controller.draggedAppID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        let added = controller.addDraggedApp(toChosenDisplay: display.id)
        controller.endDrag()
        return added
    }
}

/// One group in the arrangement: a header with the group's name and buttons, then its apps.
private struct AppGroupSection: View {
    let section: TaskbarSection
    let index: Int
    let groupCount: Int
    let groups: [TaskbarGroup]
    let controller: TaskbarController

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 6)]

    var body: some View {
        Section {
            Group {
                if section.apps.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(section.apps) { app in
                            AppIconTile(app: app, sectionID: section.id, groups: groups, controller: controller)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.text], delegate: GroupDropDelegate(section: section, controller: controller))
        } header: {
            header
        }
    }

    private var isHiddenSection: Bool { section.id == TaskbarSection.hiddenID }

    private var emptyText: String {
        if isHiddenSection { return "Drag apps here to hide them from the taskbar." }
        return section.isGroup ? "Drag apps here, or choose Add App." : "No apps yet. Choose Add App."
    }

    private var header: some View {
        HStack(spacing: 8) {
            if section.isGroup {
                Image(systemName: AppSymbol.dragHandle)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
                    .onDrag {
                        controller.beginGroupDrag(section.id)
                        return NSItemProvider(object: section.id as NSString)
                    }
                    .help("Drag to move this group")
                    .accessibilityHidden(true)

                TextField(
                    "Group Name",
                    text: Binding(
                        get: { section.name },
                        set: { controller.renameGroup(section.id, to: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(.headline)
                .frame(maxWidth: 220)
                .accessibilityLabel("Group name")
            } else {
                Text(section.name)
                    .font(.headline)
            }

            Text(section.apps.count == 1 ? "1 app" : "\(section.apps.count) apps")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if section.id != TaskbarSection.ungroupedID, !isHiddenSection {
                Button("Add App…") { chooseApps() }
                    .controlSize(.small)
            }

            if section.isGroup {
                ControlGroup {
                    Button {
                        controller.shiftGroup(section.id, by: -1)
                    } label: {
                        Image(systemName: AppSymbol.moveUp)
                    }
                    .disabled(index == 0)
                    .help("Move this group up")
                    .accessibilityLabel("Move \(section.name) up")

                    Button {
                        controller.shiftGroup(section.id, by: 1)
                    } label: {
                        Image(systemName: AppSymbol.moveDown)
                    }
                    .disabled(index >= groupCount - 1)
                    .help("Move this group down")
                    .accessibilityLabel("Move \(section.name) down")
                }
                .controlSize(.small)
                .fixedSize()

                Button {
                    controller.deleteGroup(section.id)
                } label: {
                    Image(systemName: AppSymbol.trash)
                }
                .controlSize(.small)
                .disabled(!controller.canDeleteGroup(section.id))
                .help(controller.canDeleteGroup(section.id)
                    ? "Delete this group. Its apps move to Other."
                    : "Other cannot be deleted while it holds apps.")
                .accessibilityLabel("Delete \(section.name)")
            }
        }
        .onDrop(of: [UTType.text], delegate: GroupDropDelegate(section: section, controller: controller))
    }

    /// Lets the person pick apps to keep on the taskbar. They land in this group.
    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Add Apps to the Taskbar"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        controller.addApps(at: panel.urls, toGroup: section.isGroup ? section.id : nil)
    }
}

/// One app in the arrangement. Drag it to move it, click the pin to keep it on the taskbar.
private struct AppIconTile: View {
    let app: TaskbarApp
    let sectionID: String
    let groups: [TaskbarGroup]
    let controller: TaskbarController

    /// Measured width, used to tell which half the pointer is over during a drag.
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 4) {
            icon
            Text(app.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(alignment: .topTrailing) {
            pinButton
        }
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
            }
        }
        .onDrag {
            controller.beginAppDrag(app.id)
            return NSItemProvider(object: app.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: AppTileDropDelegate(targetID: app.id, sectionID: sectionID, width: width, controller: controller)
        )
        .help(app.isRunning ? app.name : "\(app.name) (not running)")
        .contextMenu {
            menu
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = app.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: AppSymbol.applications)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
        }
    }

    /// Filled when the app is kept on the taskbar. Apps without a bundle identifier cannot be kept.
    @ViewBuilder
    private var pinButton: some View {
        if app.canBePinned {
            Button {
                controller.setPinned(!app.isPinned, app: app)
            } label: {
                Image(systemName: app.isPinned ? AppSymbol.pinned : AppSymbol.unpinned)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(app.isPinned ? Color.steadyAccent : Color.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(app.isPinned ? "Kept in the taskbar. Click to stop keeping it." : "Click to keep this app in the taskbar.")
            .accessibilityLabel(app.isPinned ? "Stop keeping \(app.name) in the taskbar" : "Keep \(app.name) in the taskbar")
        }
    }

    @ViewBuilder
    private var menu: some View {
        if app.canBePinned {
            Button(app.isPinned ? "Stop Keeping in Taskbar" : "Keep in Taskbar") {
                controller.setPinned(!app.isPinned, app: app)
            }
            if sectionID == TaskbarSection.hiddenID {
                Button("Show in Taskbar") { controller.setHiddenFromTaskbar(false, appID: app.id) }
            } else {
                Button("Hide from Taskbar") { controller.setHiddenFromTaskbar(true, appID: app.id) }
            }
            if !groups.isEmpty {
                Menu("Move to Group") {
                    ForEach(groups) { group in
                        Button(group.name.isEmpty ? "Untitled Group" : group.name) {
                            controller.moveApp(app.id, toGroup: group.id)
                        }
                        .disabled(group.id == sectionID)
                    }
                }
            }
            // Displays set to Only Apps I Choose. A check mark means the app shows there.
            let chosenDisplays = controller.chosenDisplays
            if !chosenDisplays.isEmpty {
                Menu("Show on Display") {
                    ForEach(chosenDisplays) { display in
                        Toggle(display.name, isOn: Binding(
                            get: { controller.isChosen(app.id, on: display) },
                            set: { controller.setChosen($0, appID: app.id, on: display) }
                        ))
                    }
                }
            }
        }
        if app.bundleURL != nil {
            Button("Show in Finder") { controller.showInFinder(app) }
        }
    }
}

/// Reorders apps while one is dragged across the others. The dragged app goes before the app under
/// the pointer while the pointer is over its left half, and after it over its right half.
private struct AppTileDropDelegate: DropDelegate {
    let targetID: String
    let sectionID: String
    let width: CGFloat
    let controller: TaskbarController

    func dropEntered(info: DropInfo) {
        // A group dragged over an app counts as dragged over that app's group.
        if controller.draggedGroupID != nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = controller.placeDraggedGroup(at: sectionID)
            }
        } else {
            place(info)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if controller.draggedGroupID == nil { place(info) }
        return DropProposal(operation: .move)
    }

    private func place(_ info: DropInfo) {
        guard width > 0 else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            _ = controller.placeDraggedApp(before: info.location.x < width / 2, targetID: targetID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        controller.endDrag()
        return true
    }
}

/// Handles drops on a section itself: on its header, or on the empty space around its apps.
/// A dragged app joins the group, or becomes hidden when the section is Hidden.
/// A dragged group takes this group's spot.
private struct GroupDropDelegate: DropDelegate {
    let section: TaskbarSection
    let controller: TaskbarController

    func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if controller.draggedGroupID != nil {
                if section.isGroup { _ = controller.placeDraggedGroup(at: section.id) }
            } else if section.id == TaskbarSection.hiddenID {
                _ = controller.setDraggedAppHidden(true)
            } else if section.isGroup {
                _ = controller.moveDraggedApp(toGroup: section.id)
            } else {
                _ = controller.setDraggedAppHidden(false)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        controller.endDrag()
        return true
    }
}
