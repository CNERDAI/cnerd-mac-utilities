import CoreGraphics

/// Pure window geometry. No system calls, so it is easy to unit test.
///
/// Two coordinate systems are involved:
/// - AppKit (NSScreen): origin at the bottom-left of the primary display, y grows upward.
/// - Accessibility (AXUIElement): origin at the top-left of the primary display, y grows downward.
/// Everything in the Window Manager works in Accessibility coordinates.
enum ScreenGeometry {
    /// Converts an AppKit rectangle into Accessibility coordinates.
    static func accessibilityRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The frame a window should get for a position, inside a display's usable area
    /// (the area not covered by the menu bar or Dock).
    static func targetFrame(for position: WindowPosition, in visibleFrame: CGRect, currentSize: CGSize) -> CGRect {
        switch position {
        case .maximize:
            return visibleFrame
        case .leftHalf:
            let width = (visibleFrame.width / 2).rounded(.down)
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: width, height: visibleFrame.height)
        case .rightHalf:
            let leftWidth = (visibleFrame.width / 2).rounded(.down)
            return CGRect(
                x: visibleFrame.minX + leftWidth,
                y: visibleFrame.minY,
                width: visibleFrame.width - leftWidth,
                height: visibleFrame.height
            )
        case .center:
            // Keep the window's size, but never larger than the usable area.
            let width = min(currentSize.width, visibleFrame.width)
            let height = min(currentSize.height, visibleFrame.height)
            return CGRect(
                x: (visibleFrame.midX - width / 2).rounded(),
                y: (visibleFrame.midY - height / 2).rounded(),
                width: width,
                height: height
            )
        }
    }

    /// The display a window belongs to: the one showing most of it.
    /// If the window is completely off screen, the nearest display is used.
    static func indexOfBestScreen(for windowFrame: CGRect, among screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }

        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screen) in screenFrames.enumerated() {
            let overlap = screen.intersection(windowFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if let bestIndex { return bestIndex }

        func distanceSquared(to screen: CGRect) -> CGFloat {
            let dx = windowFrame.midX - screen.midX
            let dy = windowFrame.midY - screen.midY
            return dx * dx + dy * dy
        }
        return screenFrames.indices.min { distanceSquared(to: screenFrames[$0]) < distanceSquared(to: screenFrames[$1]) }
    }

    /// True when two frames match within a few points. Apps often round or adjust the frame they are given.
    static func isApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
