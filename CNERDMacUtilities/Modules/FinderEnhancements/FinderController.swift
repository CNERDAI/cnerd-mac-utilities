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
    let quickFolders = QuickFolder.standard

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

    func open(_ folder: QuickFolder) {
        guard settings.finderEnabled else { return }
        NSWorkspace.shared.open(folder.url)
    }
}
