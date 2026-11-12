import SwiftUI

/// The main window: a fixed sidebar on the left and the selected screen on the right.
struct MainWindowView: View {
    @Environment(AppEnvironment.self) private var environment

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
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard: DashboardView()
        case .windowManager: WindowManagerSettingsView()
        case .finderEnhancements: FinderSettingsView()
        case .desktopManager: DesktopSettingsView()
        case .taskbar: TaskbarSettingsView()
        case .generalSettings: GeneralSettingsView()
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            row(.dashboard)

            Section("Utilities") {
                ForEach(SidebarItem.modules) { item in
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
                Link(AppInfo.developer, destination: AppInfo.websiteURL)
                    .font(.caption.weight(.semibold))
                    .help("Open the CNERD AI website")
                Text("Version \(AppInfo.version) · Free and open source")
                    .font(.caption)
                DonateMenu()
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
