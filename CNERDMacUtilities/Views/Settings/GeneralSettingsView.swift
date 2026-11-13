import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var settings = environment.settings
        let loginItem = environment.loginItem
        let permissions = environment.permissions

        SettingsPage(.generalSettings) {
            Section("Startup") {
                Toggle(isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                )) {
                    SettingLabel(
                        title: "Launch at Login",
                        description: "Starts CNERD Mac Utilities when you log in to your Mac."
                    )
                }

                if loginItem.needsApproval {
                    NoticeRow(text: "macOS needs your approval before this app can start at login.", kind: .warning)
                    Button("Open Login Items Settings") { loginItem.openSystemSettings() }
                }
                if let error = loginItem.lastError {
                    NoticeRow(text: "Launch at Login could not be changed: \(error)", kind: .warning)
                }

                SettingToggle(
                    title: "Show Menu Bar Icon",
                    description: "Gives quick access to window actions. It also lets you reopen this window after closing it, since the app keeps running in the background.",
                    isOn: $settings.showMenuBarIcon
                )
            }

            Section("Appearance") {
                SettingRow("Appearance", description: "Follows your macOS Light or Dark setting automatically.") {
                    Text(colorScheme == .dark ? "Dark" : "Light")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SettingRow(
                    "Accessibility",
                    description: "Needed by Window Manager to move and resize windows of other apps."
                ) {
                    if permissions.isAccessibilityTrusted {
                        StatusBadge("Granted", level: .good)
                    } else {
                        HStack {
                            StatusBadge("Not granted", level: .attention)
                            Button("Request Access…") { permissions.requestAccessibility() }
                        }
                    }
                }
                if !permissions.isAccessibilityTrusted {
                    Button("Open Accessibility Settings") { permissions.openAccessibilitySettings() }
                }

                SettingRow(
                    "Automation: Finder",
                    description: "Needed by Copy Selected File Path to ask Finder what is selected. macOS asks the first time you use it."
                ) {
                    HStack {
                        StatusBadge(permissions.finderAutomation.title, level: automationLevel)
                        Button("Open Settings") { SystemSettingsPane.automation.open() }
                    }
                }

                SettingRow(
                    "Desktop Folder",
                    description: "Needed by Desktop Manager to list the files on your Desktop. macOS asks the first time you open Desktop Manager."
                ) {
                    Button("Open Settings") { SystemSettingsPane.filesAndFolders.open() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("CNERD Mac Utilities only asks for a permission when a feature needs it. It collects no data and makes no network connections.")
            }

            Section {
                LabeledContent("Application", value: AppInfo.name)
                LabeledContent("Version", value: AppInfo.versionDisplay)
                LabeledContent("License", value: "Free and open source (MIT)")
                LabeledContent("Source Code") {
                    Link("GitHub", destination: AppInfo.sourceURL)
                        .help("Open the project on GitHub")
                }
                LabeledContent("Support Development") {
                    DonateMenu()
                }
                SettingToggle(
                    title: "I Have Donated",
                    description: "Swaps the Donate button in the sidebar and the menu bar for a thank-you. This is on the honor system. Nothing is checked or sent.",
                    isOn: $settings.hasDonated
                )
                LabeledContent("Developed by") {
                    Link(AppInfo.developer, destination: AppInfo.websiteURL)
                        .help("Open the CNERD AI website")
                }
            } header: {
                Text("About")
            } footer: {
                Text(AppInfo.trademarkNotice)
            }
        }
        .onAppear {
            loginItem.refresh()
            permissions.refreshAccessibility()
            permissions.refreshFinderAutomation()
        }
    }

    private var automationLevel: StatusBadge.Level {
        switch environment.permissions.finderAutomation {
        case .granted: .good
        case .denied: .attention
        case .notDetermined, .unavailable: .off
        }
    }
}
