import SwiftUI
import XCTest
@testable import CNERDMacUtilities

/// A right-click has to find the menu of whatever it lands on: a button at the end of the bar,
/// an app inside the scrolling list, or the bar itself.
@MainActor
final class TaskbarMenuRegionTests: XCTestCase {
    private struct Bar: View {
        var body: some View {
            HStack(spacing: 0) {
                // Like the Applications, Hidden Apps, and Trash buttons: a plain SwiftUI button.
                Button {} label: {
                    Color.blue.frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .taskbarMenu(edge: .bottom) { [.button("corner") {}] }

                // Like the apps: views inside a scroll view.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Color.red.frame(width: 40, height: 40)
                            .taskbarMenu(edge: .bottom) { [.button("app") {}] }
                        Color.green.frame(width: 40, height: 40)
                    }
                }
                .frame(width: 80, height: 40)

                Color.clear.frame(width: 80, height: 40)
            }
            .frame(width: 200, height: 40)
            .taskbarMenu(edge: .bottom) { [.button("bar") {}] }
        }
    }

    private func titles(_ panel: TaskbarPanel, x: CGFloat) -> [String] {
        panel.menuRegistry.regions(at: CGPoint(x: x, y: 20)).map { region in
            TaskbarMenuBuilder.menu(region.items()).items.first?.title ?? ""
        }
    }

    func testRightClickFindsCornerButtonsAppsAndTheBar() {
        let panel = TaskbarPanel(rootView: Bar())
        panel.alphaValue = 0
        panel.setFrame(NSRect(x: 0, y: 0, width: 200, height: 40), display: true)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        panel.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(titles(panel, x: 20), ["corner", "bar"], "A button at the end of the bar")
        XCTAssertEqual(titles(panel, x: 60), ["app", "bar"], "An app inside the scrolling list")
        XCTAssertEqual(titles(panel, x: 100), ["bar"], "An app without a menu falls back to the bar")
        XCTAssertEqual(titles(panel, x: 160), ["bar"], "The empty part of the bar")
        XCTAssertEqual(panel.menuRegistry.regions(at: CGPoint(x: 300, y: 20)).count, 0, "Outside the bar")
        XCTAssertEqual(panel.menuRegistry.regions(at: CGPoint(x: 20, y: 60)).count, 0, "Below the bar")
    }

    func testSmallestRegionComesFirst() {
        let registry = TaskbarMenuRegistry()
        let bar = UUID(), app = UUID()
        registry.set(bar, frame: CGRect(x: 0, y: 0, width: 500, height: 68), edge: .bottom) { [.button("bar") {}] }
        registry.set(app, frame: CGRect(x: 100, y: 5, width: 58, height: 58), edge: .bottom) { [.button("app") {}] }
        XCTAssertEqual(registry.regions(at: CGPoint(x: 120, y: 30)).map { $0.frame.width }, [58, 500])
        XCTAssertEqual(registry.regions(at: CGPoint(x: 300, y: 30)).map { $0.frame.width }, [500])
        // A view drawn again keeps its place and takes the new menu.
        registry.refresh(app, edge: .bottom) { [.button("new") {}] }
        XCTAssertEqual(TaskbarMenuBuilder.menu(registry.regions(at: CGPoint(x: 120, y: 30))[0].items()).items.first?.title, "new")
        registry.remove(app)
        XCTAssertEqual(registry.regions(at: CGPoint(x: 120, y: 30)).count, 1)
    }
}
