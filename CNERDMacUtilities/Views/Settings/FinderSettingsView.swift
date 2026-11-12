import SwiftUI

struct FinderSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var pendingHiddenFilesValue = false
    @State private var isConfirmingFinderRestart = false

    var body: some View {
        @Bindable var settings = environment.settings
        let finder = environment.finder

        SettingsPage(.finderEnhancements) {
            Section {
                SettingToggle(
                    title: "Enable Finder Enhancements",
                    description: "Turns the Finder tools on this page on or off.",
                    isOn: $settings.finderEnabled
                )
            }

            Section("Files") {
                Toggle(isOn: hiddenFilesBinding) {
                    SettingLabel(
                        title: "Show Hidden Files",
                        description: "Shows files and folders that macOS normally hides, such as names that start with a period. Finder restarts when this changes."
                    )
                }
                .disabled(finder.isRestartingFinder)

                if finder.isRestartingFinder {
                    NoticeRow(text: "Restarting Finder…")
                } else if let message = finder.hiddenFilesMessage {
                    NoticeRow(text: message, kind: .warning)
                }
            }
            .disabled(!settings.finderEnabled)

            Section {
                SettingRow("Copy Selected File Path", description: "Copies the full path of the files or folders selected in Finder to the clipboard.") {
                    Button {
                        finder.copySelectionPath()
                    } label: {
                        Label("Copy Path", systemImage: AppSymbol.copy)
                    }
                }

                switch finder.lastCopyResult {
                case .copied(let paths):
                    NoticeRow(text: copiedText(paths), kind: .success)
                case .failure(let message):
                    NoticeRow(text: message, kind: .warning)
                case nil:
                    EmptyView()
                }
            } header: {
                Text("Copy File Path")
            } footer: {
                Text("Select items in Finder first. macOS asks once for permission to let this app talk to Finder. The same command is in the menu bar icon.")
            }
            .disabled(!settings.finderEnabled)

            Section("Quick Access Folders") {
                ForEach(finder.quickFolders) { folder in
                    LabeledContent {
                        Button("Open") { finder.open(folder) }
                            .accessibilityLabel("Open \(folder.title) in Finder")
                    } label: {
                        Label {
                            SettingLabel(title: folder.title, description: folder.url.path)
                        } icon: {
                            Image(systemName: folder.symbolName)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .disabled(!settings.finderEnabled)
        }
        .onAppear { finder.refreshHiddenFilesState() }
        .confirmationDialog(
            "Restart Finder?",
            isPresented: $isConfirmingFinderRestart
        ) {
            Button("Restart Finder") {
                finder.setHiddenFilesVisible(pendingHiddenFilesValue)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finder has to restart to \(pendingHiddenFilesValue ? "show" : "hide") hidden files. Finder windows close and reopen. Let any file copies finish first.")
        }
    }

    /// The switch always shows Finder's real setting. A change is applied only after confirmation.
    private var hiddenFilesBinding: Binding<Bool> {
        Binding(
            get: { environment.finder.hiddenFilesVisible },
            set: { newValue in
                pendingHiddenFilesValue = newValue
                isConfirmingFinderRestart = true
            }
        )
    }

    private func copiedText(_ paths: [String]) -> String {
        guard let first = paths.first else { return "Nothing copied." }
        if paths.count == 1 { return "Copied: \(first)" }
        return "Copied \(paths.count) paths, starting with: \(first)"
    }
}
