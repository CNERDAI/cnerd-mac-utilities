import AppKit
import Observation

/// Module 002. Hidden files, path copying, and quick folder access.
@MainActor
@Observable
final class FinderController: UtilityModule {
    enum CopyResult: Equatable {
        case copied([String])
        case failure(String)
    }

    let sidebarItem = SidebarItem.finderEnhancements
    private let standardFolders = QuickFolder.standard

    /// The built-in folders, then the ones the person added.
    var quickFolders: [QuickFolder] {
        standardFolders + settings.finderQuickFolders.map { QuickFolder.custom(storedPath: $0) }
    }

    /// The folders for Finder's right-click menu on the taskbar. Empty while this module is off.
    var menuFolders: [QuickFolder] {
        settings.finderEnabled ? quickFolders : []
    }

    /// Mirrors Finder's own "show hidden files" preference.
    private(set) var hiddenFilesVisible = false
    private(set) var isRestartingFinder = false
    private(set) var hiddenFilesMessage: String?
    private(set) var lastCopyResult: CopyResult?

    private let settings: AppSettings
    private let permissions: PermissionsService

    private static let finderBundleID = "com.apple.finder"
    private static let showAllFilesKey = "AppleShowAllFiles"
    private static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    init(settings: AppSettings, permissions: PermissionsService) {
        self.settings = settings
        self.permissions = permissions
        refreshHiddenFilesState()
    }

    var status: ModuleStatus {
        settings.finderEnabled ? .active("On") : .disabled
    }

    // MARK: - Hidden files

    /// Reads the current value from Finder's preferences, so the toggle shows the real system state
    /// even if it was changed in Terminal or with Command-Shift-Period.
    func refreshHiddenFilesState() {
        let finderID = Self.finderBundleID as CFString
        CFPreferencesAppSynchronize(finderID)
        hiddenFilesVisible = CFPreferencesGetAppBooleanValue(Self.showAllFilesKey as CFString, finderID, nil)
    }

    /// Changes Finder's hidden files preference and restarts Finder so it takes effect.
    /// "AppleShowAllFiles" is the same long-standing key Finder itself writes. See docs/FEASIBILITY.md.
    func setHiddenFilesVisible(_ visible: Bool) {
        guard settings.finderEnabled, !isRestartingFinder else { return }
        let finderID = Self.finderBundleID as CFString
        CFPreferencesSetAppValue(Self.showAllFilesKey as CFString, visible as CFBoolean, finderID)
        guard CFPreferencesAppSynchronize(finderID) else {
            hiddenFilesMessage = "The setting could not be saved."
            refreshHiddenFilesState()
            return
        }
        hiddenFilesVisible = visible
        hiddenFilesMessage = nil
        restartFinder()
    }

    private func restartFinder() {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderBundleID).first else {
            launchFinder()
            return
        }
        isRestartingFinder = true
        // A normal quit request, not a forced kill. Finder can still finish or refuse if it is busy.
        finder.terminate()

        Task { @MainActor in
            for _ in 0..<50 where !finder.isTerminated {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if finder.isTerminated {
                launchFinder()
            } else {
                hiddenFilesMessage = "Finder is busy and did not restart. The change will apply the next time Finder restarts."
            }
            isRestartingFinder = false
        }
    }

    private func launchFinder() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: Self.finderURL, configuration: configuration, completionHandler: nil)
    }

    // MARK: - Copy path

    /// Copies the full path of whatever is selected in Finder to the clipboard.
    /// The first use shows the macOS prompt asking to let this app control Finder.
    func copySelectionPath() {
        guard settings.finderEnabled else { return }
        defer { permissions.refreshFinderAutomation() }

        switch Self.fetchFinderSelection() {
        case .success(let paths) where paths.isEmpty:
            lastCopyResult = .failure("Nothing is selected in Finder.")
        case .success(let paths):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
            lastCopyResult = .copied(paths)
        case .failure(let error):
            lastCopyResult = .failure(error.message)
        }
    }

    private struct SelectionError: Error {
        let message: String
    }

    /// Asks Finder for its selection through Apple Events, Apple's supported automation path.
    private static func fetchFinderSelection() -> Result<[String], SelectionError> {
        let source = """
        with timeout of 5 seconds
            tell application "Finder"
                set chosenItems to selection
                set output to ""
                repeat with anItem in chosenItems
                    set output to output & POSIX path of (anItem as alias) & linefeed
                end repeat
                return output
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else {
            return .failure(SelectionError(message: "The Finder request could not be created."))
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            switch code {
            case -1743:
                return .failure(SelectionError(message: "macOS is blocking access to Finder. Allow it in System Settings, Privacy & Security, Automation."))
            case -1712:
                return .failure(SelectionError(message: "Finder did not answer in time. Try again."))
            case -600:
                return .failure(SelectionError(message: "Finder is not running."))
            default:
                let detail = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                return .failure(SelectionError(message: "Finder returned an error: \(detail)"))
            }
        }

        let paths = (result.stringValue ?? "")
            .split(separator: "\n")
            .map { cleanedPath(String($0)) }
        return .success(paths)
    }

    /// Finder reports folders with a trailing slash. Remove it, as Finder's own "Copy as Pathname" does.
    static func cleanedPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    // MARK: - Quick folders

    /// Opens the folder in Finder. Finder does the opening, so this app needs no permission
    /// for the folder, and never looks inside it.
    func open(_ folder: QuickFolder) {
        guard settings.finderEnabled else { return }
        guard !NSWorkspace.shared.open(folder.url) else { return }
        // Wait a turn, so a right-click menu on the taskbar has closed before the message shows.
        Task { @MainActor in
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "\u{201C}\(folder.title)\u{201D} could not be opened."
            alert.informativeText = "The folder may have been moved or deleted, or it is on a disk that is not connected.\n\n\(folder.url.path)"
            alert.runModal()
        }
    }

    /// Asks which folders to add, then adds them to the end of the quick folders.
    func addFoldersWithPanel() {
        guard settings.finderEnabled else { return }
        // Wait a turn, so a right-click menu on the taskbar has closed before the chooser opens.
        Task { @MainActor [weak self] in
            let panel = NSOpenPanel()
            panel.title = "Add Quick Folders"
            panel.prompt = "Add"
            panel.message = "Choose the folders to add to your quick folders."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = true
            // The taskbar never takes the keyboard, so bring this app forward for the chooser.
            NSApp.activate()
            guard panel.runModal() == .OK else { return }
            self?.addFolders(panel.urls)
        }
    }

    /// Adds folders. One that is already in the list, built in or added, is not added twice.
    func addFolders(_ urls: [URL]) {
        let folders = QuickFolders.adding(
            urls.filter(\.isFileURL).map(\.path),
            to: settings.finderQuickFolders,
            builtIn: standardFolders.map(\.url.path)
        )
        if folders != settings.finderQuickFolders { settings.finderQuickFolders = folders }
    }

    /// Takes a folder the person added off the list. The folder itself is not touched.
    func removeFolder(_ folder: QuickFolder) {
        guard folder.isCustom else { return }
        let stored = String(folder.id.dropFirst("custom:".count))
        settings.finderQuickFolders = QuickFolders.removing(stored, from: settings.finderQuickFolders)
    }
}
