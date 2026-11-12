import AppKit

/// A snapshot of one connected display.
struct DisplayInfo: Identifiable, Equatable, Sendable {
    let id: UInt32
    let name: String
    /// Size in points, the unit macOS uses for layout.
    let pointSize: CGSize
    /// Size in physical pixels at the current scale.
    let pixelSize: CGSize
    /// Area left for windows after the menu bar and Dock.
    let visibleSize: CGSize
    let scale: CGFloat
    let isPrimary: Bool

    var resolutionText: String {
        let pixels = "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) pixels"
        guard scale != 1 else { return pixels }
        return "\(pixels) (looks like \(Int(pointSize.width)) × \(Int(pointSize.height)))"
    }

    var visibleAreaText: String {
        "\(Int(visibleSize.width)) × \(Int(visibleSize.height)) points"
    }

    /// Reads all connected displays. The first screen is the primary display (the one with the menu bar).
    @MainActor
    static func current() -> [DisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let scale = screen.backingScaleFactor
            return DisplayInfo(
                id: number?.uint32Value ?? UInt32(index),
                name: screen.localizedName,
                pointSize: screen.frame.size,
                pixelSize: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale),
                visibleSize: screen.visibleFrame.size,
                scale: scale,
                isPrimary: index == 0
            )
        }
    }
}
