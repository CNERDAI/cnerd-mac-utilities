import AppKit
import SwiftUI
import XCTest
@testable import CNERDMacUtilities

@MainActor
final class BrandLogoTests: XCTestCase {
    func testTheDeveloperLogoIsInTheAssetCatalog() {
        XCTAssertNotNil(NSImage(named: AppInfo.developerLogoAssetName), "About and the Dashboard need the CNERDAILogo image set")
    }

    /// The logo's letters are black. On a dark background the white version has to be used.
    func testTheLogoIsDarkOnLightAndWhiteOnDark() throws {
        XCTAssertLessThan(try brightness(of: logo(.light)), 0.4, "Light appearance uses the dark logo")
        XCTAssertGreaterThan(try brightness(of: logo(.dark)), 0.6, "Dark appearance uses the white logo")
    }

    /// Draws the header both ways and leaves the pictures in the temporary folder, so a person
    /// can look at them: cnerd-brand-light.png and cnerd-brand-dark.png.
    func testTheBrandHeaderDrawsInLightAndDark() throws {
        for (scheme, name, background) in [(ColorScheme.light, "light", 0.96), (ColorScheme.dark, "dark", 0.14)] {
            let view = BrandHeader()
                .padding(20)
                .frame(width: 620)
                .background(Color(white: background))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "The header should draw in \(name) appearance")
            XCTAssertGreaterThan(image.width, 1000)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("cnerd-brand-\(name).png")
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
        }
    }

    private func logo(_ scheme: ColorScheme) throws -> CGImage {
        let view = Image(AppInfo.developerLogoAssetName)
            .resizable()
            .scaledToFit()
            .frame(height: 60)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        return try XCTUnwrap(renderer.cgImage)
    }

    /// Average brightness of the drawn parts of a picture, from 0 (black) to 1 (white).
    private func brightness(of image: CGImage) throws -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var light = 0.0, weight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0 else { continue }
            // Premultiplied color, so this sum is already weighted by how solid the pixel is.
            light += (0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2])) / 255
            weight += alpha
        }
        XCTAssertGreaterThan(weight, 0, "The logo drew nothing")
        return light / max(weight, 1)
    }
}

/// Draws whole screens off screen, in light and in dark appearance, and leaves the pictures in
/// the temporary folder (cnerd-screen-<name>-<light or dark>.png) so a person can look at them.
/// The test itself only checks that each screen draws something.
@MainActor
final class ScreenDrawingTests: XCTestCase {
    func testTheDashboardDraws() throws {
        try draw("dashboard", size: NSSize(width: 640, height: 620)) { DashboardView() }
    }

    func testGeneralSettingsDraws() throws {
        try draw("general", size: NSSize(width: 640, height: 1500)) { GeneralSettingsView() }
    }

    func testFinderSettingsDraws() throws {
        try draw("finder", size: NSSize(width: 640, height: 1100)) { FinderSettingsView() }
    }

    func testTheMainWindowDraws() throws {
        try draw("window", size: NSSize(width: 900, height: 640)) { MainWindowView() }
    }

    private func draw<Content: View>(_ name: String, size: NSSize, @ViewBuilder _ content: () -> Content) throws {
        let environment = try XCTUnwrap(AppEnvironment.current, "The app that hosts the tests has an environment")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: content().environment(environment))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            window.layoutIfNeeded()
            // SwiftUI finishes its first layout a moment later.
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()

            let picture = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: picture)
            XCTAssertGreaterThan(picture.pixelsWide, 0)
            let label = appearance == .aqua ? "light" : "dark"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("cnerd-screen-\(name)-\(label).png")
            try? picture.representation(using: .png, properties: [:])?.write(to: file)
            window.close()
        }
    }
}
