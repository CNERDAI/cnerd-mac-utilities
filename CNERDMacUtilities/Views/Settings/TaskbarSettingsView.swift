import SwiftUI

struct TaskbarSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var dockSizeDraft = 0.3
    @State private var isConfirmingDockOff = false

    var body: some View {
        @Bindable var settings = environment.settings
        let taskbar = environment.taskbar

        SettingsPage(.taskbar) {
            Section {
                SettingToggle(
                    title: "Show Taskbar",
                    description: "Adds a bar along one edge of the screen with your apps. Click an app to open it or bring it forward. Click the app in front to hide it.",
                    isOn: $settings.taskbarEnabled
                )
            }

            barSection(settings: settings, taskbar: taskbar)
            appsSection(settings: settings)
            dockSection(taskbar: taskbar)
        }
        .onAppear {
            taskbar.refreshDockState()
            dockSizeDraft = taskbar.dockSize
        }
        .onChange(of: taskbar.dockSize) { _, newValue in
            dockSizeDraft = newValue
        }
        .confirmationDialog("Turn off the macOS Dock?", isPresented: $isConfirmingDockOff) {
            Button("Turn Off the Dock") { taskbar.setDockTurnedOff(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Dock restarts and then stays hidden, even when the pointer touches its edge. Apple has no official switch for this, so it uses an unofficial Dock setting. Turn this switch off at any time to bring the Dock back. Command-Tab and Mission Control keep working.")
        }
    }

    // MARK: - Sections

    private func barSection(settings: AppSettings, taskbar: TaskbarController) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.taskbarDisplayMode) {
                ForEach(TaskbarDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                SettingLabel(title: "Show On", description: "The main display is the one with the menu bar.")
            }

            Picker(selection: $settings.taskbarPosition) {
                ForEach(TaskbarPosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            } label: {
                SettingLabel(title: "Position", description: "Which edge of the screen the taskbar uses. This is separate from the Dock's position.")
            }

            Picker(selection: $settings.taskbarCornerStyle) {
                ForEach(TaskbarCornerStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            } label: {
                SettingLabel(title: "Edges", description: "Square runs edge to edge like Windows. Rounded floats off the screen edge like the Dock.")
            }

            SettingToggle(
                title: "Glass Background",
                description: "Gives the taskbar a see-through glass look. Turn off for a solid bar.",
                isOn: $settings.taskbarGlassBackground
            )

            SettingToggle(
                title: "Keep Windows Clear of the Taskbar",
                description: "Window Manager's maximize and snap stop at the edge of the taskbar instead of going behind it.",
                isOn: $settings.taskbarReserveSpace
            )

            if settings.taskbarEnabled {
                if taskbar.visibleBarCount == 0 {
                    NoticeRow(text: "No connected display matches this setting, so no taskbar is showing.", kind: .warning)
                } else {
                    NoticeRow(
                        text: taskbar.visibleBarCount == 1 ? "Showing on 1 display." : "Showing on \(taskbar.visibleBarCount) displays.",
                        kind: .success
                    )
                }
            }
        } header: {
            Text("Taskbar")
        } footer: {
            Text("The taskbar always sits in the free space next to the Dock. When the Dock hides or is turned off, the taskbar slides into its place. macOS only lets the Dock reserve screen space, so windows sized by hand can sit behind the taskbar.")
        }
        .disabled(!settings.taskbarEnabled)
    }

    private func appsSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.taskbarIconSize) {
                ForEach(TaskbarIconSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            } label: {
                SettingLabel(title: "Icon Size", description: "The size of app icons on the taskbar.")
            }

            SettingToggle(
                title: "Show App Names",
                description: "Shows each app's name with its icon. Turn off for icons only.",
                isOn: $settings.taskbarShowAppNames
            )

            Picker(selection: $settings.taskbarNamePosition) {
                ForEach(TaskbarNamePosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            } label: {
                SettingLabel(title: "App Name Position", description: "Where the name sits next to the icon.")
            }
            .disabled(!settings.taskbarShowAppNames)

            Picker(selection: $settings.taskbarNameSize) {
                ForEach(TaskbarNameSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            } label: {
                SettingLabel(title: "App Name Size", description: "The text size of app names.")
            }
            .disabled(!settings.taskbarShowAppNames)

            SettingToggle(
                title: "Show Trash",
                description: "Adds the Trash at the end of the taskbar. Click it to open the Trash in Finder.",
                isOn: $settings.taskbarShowTrash
            )
        } header: {
            Text("Apps on the Taskbar")
        } footer: {
            Text("Drag an app along the taskbar to move it. The order is saved. Right-click an app for Keep in Taskbar, Show All Windows, Show in Finder, Hide, and Quit.")
        }
        .disabled(!settings.taskbarEnabled)
    }

    private func dockSection(taskbar: TaskbarController) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { taskbar.isDockTurnedOff },
                set: { turnOff in
                    if turnOff {
                        isConfirmingDockOff = true
                    } else {
                        taskbar.setDockTurnedOff(false)
                    }
                }
            )) {
                SettingLabel(
                    title: "Turn Off the macOS Dock",
                    description: "Hides the Dock completely so only the taskbar shows. Turn this off whenever you need the Dock back."
                )
            }

            Toggle(isOn: Binding(
                get: { taskbar.dockAutoHide },
                set: { taskbar.setDockAutoHide($0) }
            )) {
                SettingLabel(
                    title: "Automatically Hide the Dock",
                    description: "The Dock slides away until the pointer reaches its edge of the screen."
                )
            }
            .disabled(taskbar.isDockTurnedOff)

            Picker(selection: Binding(
                get: { taskbar.dockPosition },
                set: { taskbar.setDockPosition($0) }
            )) {
                ForEach(DockPosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            } label: {
                SettingLabel(title: "Dock Position", description: "Which edge of the screen the Dock uses.")
            }

            LabeledContent {
                Slider(value: $dockSizeDraft, in: 0...1, onEditingChanged: { editing in
                    if !editing { taskbar.setDockSize(dockSizeDraft) }
                })
                .frame(width: 200)
                .accessibilityLabel("Dock size")
            } label: {
                SettingLabel(title: "Dock Size", description: "Applied when you release the slider.")
            }

            if let message = taskbar.dockMessage {
                NoticeRow(text: message, kind: .warning)
            }
        } header: {
            Text("macOS Dock")
        } footer: {
            Text("Auto-hide, position, and size change the real Dock through System Events. macOS asks once for permission. macOS shows the Dock on one display at a time and offers no way to change that.")
        }
    }
}
