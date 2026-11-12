import Foundation

/// What a module reports to the Dashboard.
enum ModuleStatus: Equatable, Sendable {
    case active(String)
    case disabled
    case needsAttention(String)

    var text: String {
        switch self {
        case .active(let detail): detail
        case .disabled: "Off"
        case .needsAttention(let detail): detail
        }
    }
}

/// The small contract every utility module shares.
/// Modules own their system logic. Views only read state and call methods.
@MainActor
protocol UtilityModule: AnyObject {
    var sidebarItem: SidebarItem { get }
    var status: ModuleStatus { get }
}
