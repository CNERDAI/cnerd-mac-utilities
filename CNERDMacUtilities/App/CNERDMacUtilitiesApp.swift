import SwiftUI

@main
struct CNERDMacUtilitiesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        Window(AppInfo.name, id: WindowID.main) {
            MainWindowView()
                .environment(environment)
        }
        .defaultSize(width: 880, height: 640)
        .windowResizability(.contentMinSize)

        MenuBarExtra(AppInfo.name, systemImage: AppSymbol.menuBar, isInserted: menuBarIconBinding) {
            MenuBarContent()
                .environment(environment)
        }
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { environment.settings.showMenuBarIcon },
            set: { environment.settings.showMenuBarIcon = $0 }
        )
    }
}
