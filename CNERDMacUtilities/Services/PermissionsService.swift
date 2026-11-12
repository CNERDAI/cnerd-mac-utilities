import AppKit
import ApplicationServices
import Observation

/// Whether this app may send Apple Events to another app.
enum AutomationStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case unavailable

    var title: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested yet"
        case .unavailable: "Unknown"
        }
    }
}

/// Deep links into macOS System Settings.
enum SystemSettingsPane: Sendable {
    case accessibility
    case automation
    case filesAndFolders
    case desktopAndDock

    var url: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
        case .automation:
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation")
        case .filesAndFolders:
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders")
        case .desktopAndDock:
            URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
        }
    }

    @MainActor
    func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Tracks the macOS permissions the app depends on.
/// It never asks for a permission on its own. Requests only happen when the user clicks a button.
@MainActor
@Observable
final class PermissionsService {
    private(set) var isAccessibilityTrusted: Bool
    private(set) var finderAutomation: AutomationStatus = .notDetermined

    @ObservationIgnored private var grantWatchTimer: Timer?
    @ObservationIgnored private var grantWatchDeadline: Date?

    init() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        // Event driven: check again whenever the user comes back to the app.
        NotificationCenter.default.observeOnMain(NSApplication.didBecomeActiveNotification) { [weak self] in
            self?.refreshAccessibility()
        }
    }

    // MARK: - Accessibility

    /// Re-reads the Accessibility permission and tells the rest of the app if it changed.
    func refreshAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted { stopWatchingForGrant() }
        guard trusted != isAccessibilityTrusted else { return }
        isAccessibilityTrusted = trusted
        NotificationCenter.default.post(name: .accessibilityTrustDidChange, object: nil)
    }

    /// Shows the macOS Accessibility prompt. macOS only shows it the first time,
    /// so the System Settings pane is opened as well when the prompt was already used.
    func requestAccessibility() {
        // The literal is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        watchForGrant()
    }

    func openAccessibilitySettings() {
        SystemSettingsPane.accessibility.open()
        watchForGrant()
    }

    /// Checks for the grant every two seconds, for at most five minutes, after the user asked for it.
    /// This is the only timer in the app and it stops as soon as access is granted.
    private func watchForGrant() {
        guard !isAccessibilityTrusted else { return }
        grantWatchDeadline = Date().addingTimeInterval(300)
        guard grantWatchTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let deadline = self.grantWatchDeadline, Date() > deadline {
                    self.stopWatchingForGrant()
                } else {
                    self.refreshAccessibility()
                }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        grantWatchTimer = timer
    }

    private func stopWatchingForGrant() {
        grantWatchTimer?.invalidate()
        grantWatchTimer = nil
        grantWatchDeadline = nil
    }

    // MARK: - Automation (Finder)

    /// Reads the Automation permission for Finder without showing a prompt.
    func refreshFinderAutomation() {
        let finderID = "com.apple.finder"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: finderID).isEmpty else {
            finderAutomation = .unavailable
            return
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: finderID)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        )
        switch Int(status) {
        case 0: finderAutomation = .granted
        case -1743: finderAutomation = .denied            // errAEEventNotPermitted
        case -1744: finderAutomation = .notDetermined     // errAEEventWouldRequireUserConsent
        default: finderAutomation = .unavailable
        }
    }
}
