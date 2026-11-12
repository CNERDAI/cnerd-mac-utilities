import Foundation
import Observation
import ServiceManagement

/// Launch at login, using Apple's supported SMAppService API.
@MainActor
@Observable
final class LoginItemService {
    private(set) var status: SMAppService.Status
    private(set) var lastError: String?

    init() {
        status = SMAppService.mainApp.status
    }

    var isEnabled: Bool { status == .enabled }

    var needsApproval: Bool { status == .requiresApproval }

    var statusText: String {
        switch status {
        case .enabled: "On"
        case .requiresApproval: "Needs approval in System Settings"
        case .notRegistered, .notFound: "Off"
        @unknown default: "Unknown"
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
