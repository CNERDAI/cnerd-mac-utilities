import AppKit
import SwiftUI

/// The menu shown by the menu bar icon. Gives quick access while the main window is closed.
struct MenuBarContent: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = environment.settings
        let windowManager = environment.windowManager

        ForEach(WindowPosition.allCases) { position in
            Button(position.title) {
                windowManager.perform(position, target: .lastOtherApp)
            }
            .disabled(!windowManager.canPerform(position))
        }

        Divider()

        Button("Copy Finder Selection Path") {
            environment.finder.copySelectionPath()
        }
        .disabled(!environment.settings.finderEnabled)

        // One switch between this app's taskbar and the Apple Dock. This is the way back to the
        // taskbar while the Apple Dock is in use.
        Button(environment.taskbar.barMode.switchTitle) {
            environment.taskbar.toggleBar()
        }

        Divider()

        Button("Open \(AppInfo.name)…") {
            openWindow(id: WindowID.main)
            NSApp.activate()
        }

        if !environment.settings.hasDonated {
            Menu("Donate") {
                ForEach(AppInfo.donationAmounts, id: \.self) { amount in
                    Button("$\(amount)") { NSWorkspace.shared.open(AppInfo.donateURL(amount: amount)) }
                }
            }
        }

        Button("Quit \(AppInfo.name)") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
