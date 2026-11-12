import Foundation

/// The window positions available in Version 1.0.
enum WindowPosition: String, CaseIterable, Identifiable, Sendable {
    case maximize
    case leftHalf
    case rightHalf
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maximize: "Maximize / Restore"
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .center: "Center"
        }
    }

    var symbolName: String {
        switch self {
        case .maximize: "rectangle.inset.filled"
        case .leftHalf: "rectangle.lefthalf.inset.filled"
        case .rightHalf: "rectangle.righthalf.inset.filled"
        case .center: "rectangle.center.inset.filled"
        }
    }
}
