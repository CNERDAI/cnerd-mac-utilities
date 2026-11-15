import SwiftUI

/// The main window: a fixed sidebar on the left and the selected screen on the right.
struct MainWindowView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var navigation = environment.navigation

        NavigationSplitView {
            SidebarView(selection: $navigation.selection)
                // Wide enough for the longest title in the bold selected state.
                .frame(minWidth: 240)
                .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 300)
        } detail: {
            detail(for: navigation.selection ?? .dashboard)
        }
        .frame(minWidth: 820, minHeight: 540)
        .onAppear {
            // Lets the taskbar reopen this window after it was closed.
            environment.navigation.openMainWindow = { openWindow(id: WindowID.main) }
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard: DashboardView()
        case .windowManager: WindowManagerSettingsView()
        case .finderEnhancements: FinderSettingsView()
        case .desktopManager: DesktopSettingsView()
        case .taskbar: TaskbarSettingsView()
        case .appIcons: AppIconsSettingsView()
        case .generalSettings: GeneralSettingsView()
        }
    }
}

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            row(.dashboard)

            Section("Utilities") {
                ForEach(SidebarItem.utilities) { item in
                    row(item)
                }
            }

            Section {
                row(.generalSettings)
            }
        }
        .listStyle(.sidebar)
        .toolbar(removing: .sidebarToggle)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                // The app's logo, shown above the CNERD AI name. This is the artwork itself.
                // The app icon from macOS comes with a light plate around it, which read as a border.
                Image(AppInfo.logoAssetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .padding(.bottom, 5)
                    .accessibilityLabel(AppInfo.name)
                DeveloperLogoLink(height: 15)
                    .padding(.bottom, 3)
                // The build number shows too, so it is clear which build is running.
                Text("Version \(AppInfo.versionDisplay)")
                    .font(.caption)
                Text("Free and open source")
                    .font(.caption)
                Group {
                    if environment.settings.hasDonated {
                        SupporterThanks()
                    } else {
                        DonateMenu()
                    }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label {
            Text(item.title)
        } icon: {
            TintedIcon(symbolName: item.symbolName, tint: item.tint, size: 20)
        }
        .tag(item)
    }
}
