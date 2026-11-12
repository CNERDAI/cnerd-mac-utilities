import XCTest
@testable import CNERDMacUtilities

final class ScreenGeometryTests: XCTestCase {
    /// A 1440 x 900 display with a 25 pt menu bar and a 70 pt Dock, in Accessibility coordinates.
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 805)

    func testAppKitToAccessibilityConversionFlipsY() {
        // AppKit: visible area starts 70 pt above the bottom of a 900 pt tall primary display.
        let appKit = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let converted = ScreenGeometry.accessibilityRect(fromAppKit: appKit, primaryScreenHeight: 900)
        XCTAssertEqual(converted, visible)
    }

    func testConversionForDisplayAbovePrimary() {
        // A second display sitting on top of the primary has a negative Accessibility y.
        let appKit = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let converted = ScreenGeometry.accessibilityRect(fromAppKit: appKit, primaryScreenHeight: 900)
        XCTAssertEqual(converted, CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    func testMaximizeFillsUsableArea() {
        let frame = ScreenGeometry.targetFrame(for: .maximize, in: visible, currentSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(frame, visible)
    }

    func testHalvesCoverUsableAreaWithoutOverlap() {
        let odd = CGRect(x: 100, y: 25, width: 1441, height: 805)
        let left = ScreenGeometry.targetFrame(for: .leftHalf, in: odd, currentSize: .zero)
        let right = ScreenGeometry.targetFrame(for: .rightHalf, in: odd, currentSize: .zero)
        XCTAssertEqual(left.minX, odd.minX)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(right.maxX, odd.maxX)
        XCTAssertEqual(left.height, odd.height)
        XCTAssertEqual(right.height, odd.height)
    }

    func testCenterKeepsSizeAndCenters() {
        let frame = ScreenGeometry.targetFrame(for: .center, in: visible, currentSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(frame.size, CGSize(width: 800, height: 600))
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 1)
    }

    func testCenterShrinksOversizedWindow() {
        let frame = ScreenGeometry.targetFrame(for: .center, in: visible, currentSize: CGSize(width: 5000, height: 5000))
        XCTAssertEqual(frame, visible)
    }

    func testBestScreenIsTheOneShowingMostOfTheWindow() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let mostlyOnSecond = CGRect(x: 1300, y: 100, width: 800, height: 600)
        XCTAssertEqual(ScreenGeometry.indexOfBestScreen(for: mostlyOnSecond, among: screens), 1)
        let onFirst = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(ScreenGeometry.indexOfBestScreen(for: onFirst, among: screens), 0)
    }

    func testOffScreenWindowUsesNearestScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let farRight = CGRect(x: 9000, y: 100, width: 400, height: 300)
        XCTAssertEqual(ScreenGeometry.indexOfBestScreen(for: farRight, among: screens), 1)
        XCTAssertNil(ScreenGeometry.indexOfBestScreen(for: farRight, among: []))
    }

    func testApproximateEquality() {
        let a = CGRect(x: 0, y: 25, width: 1440, height: 805)
        XCTAssertTrue(ScreenGeometry.isApproximatelyEqual(a, a.offsetBy(dx: 3, dy: -3)))
        XCTAssertFalse(ScreenGeometry.isApproximatelyEqual(a, a.offsetBy(dx: 40, dy: 0)))
        XCTAssertFalse(ScreenGeometry.isApproximatelyEqual(a, CGRect(x: 0, y: 25, width: 1300, height: 805)))
    }
}
