import AppKit
import Observation

/// Module 003. Read-only view of Desktop files, plus display information.
/// This module never moves, renames, or deletes anything.
@MainActor
@Observable
final class DesktopController: UtilityModule {
    enum ContentsState: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed(String)
    }

    let sidebarItem = SidebarItem.desktopManager

    private(set) var displays: [DisplayInfo] = []
    private(set) var items: [DesktopItem] = []
    private(set) var contentsState: ContentsState = .notLoaded

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        refreshDisplays()
        // Event driven: macOS posts this when displays are connected, removed, or rearranged.
        NotificationCenter.default.observeOnMain(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.refreshDisplays()
        }
    }

    var status: ModuleStatus {
        settings.desktopEnabled ? .active("On") : .disabled
    }

    var desktopURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    /// Desktop items in the order chosen in settings. Only the list in the app is sorted.
    var sortedItems: [DesktopItem] {
        DesktopItem.sorted(items, by: settings.desktopSortOrder)
    }

    // MARK: - Displays

    func refreshDisplays() {
        let current = DisplayInfo.current()
        if current != displays { displays = current }
    }

    // MARK: - Desktop files

    /// Reads the Desktop folder in the background. The first call makes macOS ask
    /// for permission to access the Desktop folder.
    func loadDesktopContents() {
        guard settings.desktopEnabled, contentsState != .loading else { return }
        contentsState = .loading
        let url = desktopURL

        Task {
            let result: Result<[DesktopItem], DesktopLoadError> = await Task.detached(priority: .userInitiated) { () -> Result<[DesktopItem], DesktopLoadError> in
                do {
                    return .success(try DesktopItem.load(from: url))
                } catch let error as CocoaError where error.code == .fileReadNoPermission {
                    return .failure(.noPermission)
                } catch {
                    return .failure(.other(error.localizedDescription))
                }
            }.value

            switch result {
            case .success(let loaded):
                items = loaded
                contentsState = .loaded
            case .failure(.noPermission):
                items = []
                contentsState = .failed("macOS is blocking access to the Desktop folder. Allow it in System Settings, Privacy & Security, Files and Folders.")
            case .failure(.other(let detail)):
                items = []
                contentsState = .failed("The Desktop folder could not be read: \(detail)")
            }
        }
    }

    func openDesktopFolder() {
        guard settings.desktopEnabled else { return }
        NSWorkspace.shared.open(desktopURL)
    }

    /// Shows the item in Finder without opening it.
    func reveal(_ item: DesktopItem) {
        guard settings.desktopEnabled else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}

private enum DesktopLoadError: Error, Sendable {
    case noPermission
    case other(String)
}
