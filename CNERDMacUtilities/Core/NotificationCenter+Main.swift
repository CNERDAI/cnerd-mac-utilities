import Foundation

extension Notification.Name {
    /// Posted after any stored preference changes.
    static let appSettingsDidChange = Notification.Name("ai.cnerd.MacUtilities.settingsDidChange")
    /// Posted when the Accessibility permission is granted or removed.
    static let accessibilityTrustDidChange = Notification.Name("ai.cnerd.MacUtilities.accessibilityTrustDidChange")
}

extension NotificationCenter {
    /// Adds an observer that is delivered on the main queue and runs on the main actor.
    /// Observers added this way live for the lifetime of the app.
    @MainActor
    func observeOnMain(_ name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        _ = addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
