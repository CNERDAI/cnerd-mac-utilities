import SwiftUI

struct WindowManagerSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        let windowManager = environment.windowManager
        let isTrusted = environment.permissions.isAccessibilityTrusted

        SettingsPage(.windowManager) {
            Section {
                SettingToggle(
                    title: "Enable Window Manager",
                    description: "Turns all window features on or off. When off, the app does not touch any window.",
                    isOn: $settings.windowManagerEnabled
                )
            }

            if settings.windowManagerEnabled, !isTrusted {
                Section("Permission Needed") {
                    NoticeRow(
                        text: "macOS requires the Accessibility permission before any app can move or resize windows of other apps. Nothing below works until it is granted.",
                        kind: .warning
                    )
                    SettingRow("Accessibility", description: "Add CNERD Mac Utilities in Privacy & Security, Accessibility.") {
                        HStack {
                            Button("Request Access…") { environment.permissions.requestAccessibility() }
                            Button("Open Settings") { environment.permissions.openAccessibilitySettings() }
                        }
                    }
                }
            }

            Section("Window Behavior") {
                SettingToggle(
                    title: "Windows-Style Maximize",
                    description: "Maximize fills the usable desktop and keeps the menu bar and Dock. It does not enter Full Screen. Use it again to restore the original size and position.",
                    isOn: $settings.maximizeEnabled
                )

                SettingToggle(
                    title: "Use the Green Window Button (Beta)",
                    description: "Clicking a window's green button maximizes or restores it instead of entering Full Screen. Option-click keeps the macOS behavior. Apps that draw their own window buttons are not affected.",
                    isOn: $settings.greenButtonEnabled
                )
                .disabled(!settings.maximizeEnabled)

                if settings.greenButtonEnabled, settings.maximizeEnabled, settings.windowManagerEnabled, isTrusted, !windowManager.isGreenButtonActive {
                    NoticeRow(
                        text: "macOS did not allow the green button to be watched. Quit and reopen CNERD Mac Utilities, then try again.",
                        kind: .warning
                    )
                }

                SettingToggle(
                    title: "Enable Window Snapping",
                    description: "Move a window to the left half, the right half, or the center of its display.",
                    isOn: $settings.snappingEnabled
                )

                SettingToggle(
                    title: "Enable Keyboard Shortcuts",
                    description: "Use the shortcuts below from any app.",
                    isOn: $settings.windowShortcutsEnabled
                )
            }
            .disabled(!settings.windowManagerEnabled)

            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(WindowPosition.allCases) { position in
                        Button {
                            windowManager.perform(position, target: .lastOtherApp)
                        } label: {
                            Label(position.title, systemImage: position.symbolName)
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(!windowManager.canPerform(position))
                    }
                }
                .padding(.vertical, 2)

                if let result = windowManager.lastResult {
                    NoticeRow(text: result.text, kind: result.isFailure ? .warning : .success)
                }
            } header: {
                Text("Window Positioning")
            } footer: {
                Text(positioningFooter)
            }

            Section {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRecorderRow(action: action)
                }
                SettingRow("Restore Defaults", description: "Control-Option with the arrow keys and C.") {
                    Button("Reset") { settings.resetShortcuts() }
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Click a shortcut, then press the new keys. Shortcuts that macOS already uses are not accepted.")
            }
            .disabled(!settings.windowManagerEnabled || !settings.windowShortcutsEnabled)
        }
    }

    private var positioningFooter: String {
        if let name = environment.windowManager.lastOtherAppName {
            return "These buttons act on the front window of the app you used last: \(name)."
        }
        return "These buttons act on the front window of the app you used last. Switch to another app once so there is a window to move."
    }
}
