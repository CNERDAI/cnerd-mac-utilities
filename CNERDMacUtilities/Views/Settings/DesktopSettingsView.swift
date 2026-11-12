import AppKit
import SwiftUI

struct DesktopSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Keeps the page short on very full desktops.
    private static let visibleItemLimit = 60

    var body: some View {
        @Bindable var settings = environment.settings
        let desktop = environment.desktop

        SettingsPage(.desktopManager) {
            Section {
                SettingToggle(
                    title: "Enable Desktop Manager",
                    description: "Turns the desktop tools on this page on or off.",
                    isOn: $settings.desktopEnabled
                )
            }

            Section {
                SettingRow(
                    "Desktop Icon Visibility",
                    description: "Not included in this version. Apple has no supported way for apps to hide desktop icons. macOS has its own switch under Desktop & Dock, Show Items, On Desktop."
                ) {
                    Button("Open Desktop & Dock") { SystemSettingsPane.desktopAndDock.open() }
                }
            } header: {
                Text("Desktop Icons")
            }

            Section {
                Picker(selection: $settings.desktopSortOrder) {
                    ForEach(DesktopSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                } label: {
                    SettingLabel(title: "Sort By", description: "Sorts this list only. Icons on your desktop stay where they are.")
                }

                SettingRow("Desktop Folder", description: desktop.desktopURL.path) {
                    HStack {
                        Button {
                            desktop.loadDesktopContents()
                        } label: {
                            Label("Refresh", systemImage: AppSymbol.refresh)
                        }
                        Button("Open in Finder") { desktop.openDesktopFolder() }
                    }
                }

                desktopContents(desktop)
            } header: {
                Text("Desktop Organization")
            } footer: {
                Text("This list is read-only. CNERD Mac Utilities never moves, renames, or deletes your files.")
            }
            .disabled(!settings.desktopEnabled)

            Section("Display Information") {
                if desktop.displays.isEmpty {
                    NoticeRow(text: "No displays found.")
                }
                ForEach(desktop.displays) { display in
                    displayRow(display)
                }
            }
            .disabled(!settings.desktopEnabled)
        }
        .onAppear {
            desktop.refreshDisplays()
            if desktop.contentsState == .notLoaded {
                desktop.loadDesktopContents()
            }
        }
    }

    @ViewBuilder
    private func desktopContents(_ desktop: DesktopController) -> some View {
        switch desktop.contentsState {
        case .notLoaded:
            NoticeRow(text: "Desktop files have not been loaded yet.")
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the Desktop folder…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            NoticeRow(text: message, kind: .warning)
            Button("Open Privacy Settings") { SystemSettingsPane.filesAndFolders.open() }
        case .loaded:
            let items = desktop.sortedItems
            if items.isEmpty {
                NoticeRow(text: "Your Desktop folder is empty.")
            } else {
                ForEach(items.prefix(Self.visibleItemLimit)) { item in
                    itemRow(item, desktop: desktop)
                }
                if items.count > Self.visibleItemLimit {
                    NoticeRow(text: "Showing \(Self.visibleItemLimit) of \(items.count) items. Open the folder in Finder to see all of them.")
                }
            }
        }
    }

    private func itemRow(_ item: DesktopItem, desktop: DesktopController) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let modified = item.modified {
                Text(modified.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Show") { desktop.reveal(item) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show \(item.name) in Finder")
        }
    }

    private func displayRow(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: AppSymbol.display)
                    .foregroundStyle(.tint)
                Text(display.name)
                    .font(.headline)
                if display.isPrimary {
                    Text("Primary")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
            LabeledContent("Resolution", value: display.resolutionText)
                .font(.callout)
            LabeledContent("Available Desktop Area", value: display.visibleAreaText)
                .font(.callout)
        }
        .padding(.vertical, 4)
    }
}
