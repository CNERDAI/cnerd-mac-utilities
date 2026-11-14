import SwiftUI
import XCTest
@testable import CNERDMacUtilities

/// Which edge a dragged taskbar lands on. Screen coordinates, with y growing upward.
final class TaskbarDragEdgeTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)

    func testPointerNearAnEdgePicksThatEdge() {
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 800, y: 20), in: screen, current: .top), .bottom)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 800, y: 880), in: screen, current: .bottom), .top)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 20, y: 450), in: screen, current: .bottom), .left)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 1580, y: 450), in: screen, current: .bottom), .right)
    }

    func testDisplayIsCutAlongItsDiagonals() {
        // A quarter of the way across and a third of the way up: the left edge is closer.
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 400, y: 300), in: screen, current: .top), .left)
        // A quarter of the way across and a sixth of the way up: the bottom edge is closer.
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 400, y: 150), in: screen, current: .top), .bottom)
    }

    func testTargetStaysUntilAnotherEdgeIsClearlyCloser() {
        // The left edge is closer by 2 percent of the display. Not enough to change the target.
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 448, y: 270), in: screen, current: .bottom), .bottom)
        // Closer by 5 percent. Now it changes.
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 400, y: 270), in: screen, current: .bottom), .left)
        // A short drag along the bar itself never leaves its edge.
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 900, y: 30), in: screen, current: .bottom), .bottom)
    }

    func testPointerOutsideTheDisplayCountsAsItsNearestEdge() {
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: -500, y: 450), in: screen, current: .bottom), .left)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 800, y: 2000), in: screen, current: .bottom), .top)
    }

    func testDisplayAwayFromTheOrigin() {
        // A display above the main one, like the third display on the test Mac.
        let upper = CGRect(x: 333, y: 982, width: 1024, height: 600)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 845, y: 990), in: upper, current: .top), .bottom)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 1350, y: 1280), in: upper, current: .bottom), .right)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 845, y: 1575), in: upper, current: .bottom), .top)
    }

    func testDisplayWithNoSizeKeepsTheCurrentEdge() {
        XCTAssertEqual(TaskbarLayout.dragEdge(for: CGPoint(x: 5, y: 5), in: .zero, current: .right), .right)
    }

    func testDragThatStaysOnTheBarNeverMovesIt() {
        // A rounded bar along the bottom of a 1512 by 982 display, like the test Mac's main display.
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let bar = CGRect(x: 6, y: 6, width: 1500, height: 55)
        // The top left corner of the bar is closer to the left edge than to the bottom edge.
        let corner = CGPoint(x: 8, y: 60)
        XCTAssertEqual(TaskbarLayout.dragEdge(for: corner, in: display, current: .bottom), .left)
        // But it is still on the bar, so the bar stays where it is.
        XCTAssertEqual(
            TaskbarLayout.dragTarget(for: corner, bar: bar, home: .bottom, screen: display, current: .bottom), .bottom
        )
        // Coming back onto the bar from another target also goes home.
        XCTAssertEqual(
            TaskbarLayout.dragTarget(for: CGPoint(x: 700, y: 30), bar: bar, home: .bottom, screen: display, current: .left), .bottom
        )
        // Well clear of the bar, the nearest edge decides.
        XCTAssertEqual(
            TaskbarLayout.dragTarget(for: CGPoint(x: 8, y: 400), bar: bar, home: .bottom, screen: display, current: .bottom), .left
        )
        XCTAssertEqual(
            TaskbarLayout.dragTarget(for: CGPoint(x: 756, y: 900), bar: bar, home: .bottom, screen: display, current: .bottom), .top
        )
    }

    func testPreviewOnASideEdgeIsAsThickAsTheBarWillBe() {
        // Names beside the icons make a side bar much wider than a bottom bar is tall.
        let bottom = TaskbarLayout.thickness(position: .bottom, iconSize: 26, showNames: true, namePosition: .right, nameSize: 10)
        let left = TaskbarLayout.thickness(position: .left, iconSize: 26, showNames: true, namePosition: .right, nameSize: 10)
        XCTAssertGreaterThan(left, bottom)
        let frame = TaskbarLayout.frame(in: screen, position: .left, thickness: left)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: left, height: 900))
    }
}

/// A press on the empty part of a taskbar can be dragged. A press on a button or an app cannot.
@MainActor
final class TaskbarBarDragTests: XCTestCase {
    private struct Bar: View {
        var body: some View {
            HStack(spacing: 0) {
                Button {} label: {
                    Color.blue.frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .taskbarMenu(edge: .bottom) { [.button("button") {}] }

                Color.clear.frame(width: 160, height: 40)
            }
            .frame(width: 200, height: 40)
            .taskbarMenu(edge: .bottom, isBar: true) { [.button("bar") {}] }
        }
    }

    private func makePanel() -> TaskbarPanel {
        let panel = TaskbarPanel(rootView: Bar())
        panel.alphaValue = 0
        panel.setFrame(NSRect(x: 0, y: 0, width: 200, height: 40), display: true)
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return panel
    }

    private func send(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, to panel: TaskbarPanel) {
        guard let event = NSEvent.mouseEvent(
            with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) else {
            XCTFail("Could not make a mouse event")
            return
        }
        panel.sendEvent(event)
    }

    func testOnlyThePartWithNoButtonIsEmpty() {
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        XCTAssertTrue(panel.menuRegistry.isEmptyBar(at: CGPoint(x: 120, y: 20)), "Beside the button")
        XCTAssertFalse(panel.menuRegistry.isEmptyBar(at: CGPoint(x: 20, y: 20)), "On the button")
        XCTAssertFalse(panel.menuRegistry.isEmptyBar(at: CGPoint(x: 300, y: 20)), "Off the bar")
    }

    func testDragFromTheEmptyPartReportsTheMoveAndTheEnd() {
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        var phases: [TaskbarPanel.BarDragPhase] = []
        panel.onBarDrag = { phases.append($0) }

        send(.leftMouseDown, x: 120, y: 20, to: panel)
        // A few points is a shaky click, not a drag.
        send(.leftMouseDragged, x: 123, y: 22, to: panel)
        XCTAssertEqual(phases, [])
        send(.leftMouseDragged, x: 120, y: 300, to: panel)
        send(.leftMouseUp, x: 120, y: 300, to: panel)

        let landed = panel.convertPoint(toScreen: NSPoint(x: 120, y: 300))
        XCTAssertEqual(phases, [.moved(landed), .ended(landed)])
    }

    func testClickOnTheEmptyPartIsNotADrag() {
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        var phases: [TaskbarPanel.BarDragPhase] = []
        panel.onBarDrag = { phases.append($0) }

        send(.leftMouseDown, x: 120, y: 20, to: panel)
        send(.leftMouseUp, x: 120, y: 20, to: panel)
        XCTAssertEqual(phases, [])
    }

    func testPressOnAButtonIsNotADrag() {
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        var phases: [TaskbarPanel.BarDragPhase] = []
        panel.onBarDrag = { phases.append($0) }

        send(.leftMouseDown, x: 20, y: 20, to: panel)
        send(.leftMouseDragged, x: 20, y: 300, to: panel)
        send(.leftMouseUp, x: 20, y: 300, to: panel)
        XCTAssertEqual(phases, [])
    }

    func testCancelledDragDoesNotLand() {
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        var phases: [TaskbarPanel.BarDragPhase] = []
        panel.onBarDrag = { phases.append($0) }

        send(.leftMouseDown, x: 120, y: 20, to: panel)
        send(.leftMouseDragged, x: 120, y: 300, to: panel)
        panel.cancelBarDrag()
        send(.leftMouseUp, x: 120, y: 300, to: panel)

        let moved = panel.convertPoint(toScreen: NSPoint(x: 120, y: 300))
        XCTAssertEqual(phases, [.moved(moved), .cancelled])
    }

    func testPanelWithoutADragHandlerLeavesThePressAlone() {
        // A pop-up has no handler. A press on it goes on to SwiftUI as before.
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        send(.leftMouseDown, x: 120, y: 20, to: panel)
        send(.leftMouseDragged, x: 120, y: 300, to: panel)
        send(.leftMouseUp, x: 120, y: 300, to: panel)
    }
}

/// The Dock comes back when the app quits, and goes off again at the next launch.
@MainActor
final class DockAtQuitSettingTests: XCTestCase {
    func testFlagIsOffByDefaultAndPersists() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertFalse(first.dockOffAgainAtLaunch)
        first.dockOffAgainAtLaunch = true
        XCTAssertTrue(AppSettings(defaults: defaults).dockOffAgainAtLaunch)
    }

    func testTheTestHostNeverTouchesTheRealDock() {
        XCTAssertTrue(AppInfo.isRunningTests)
    }
}

/// Getting apps onto the taskbar from the Apple Dock and from Finder.
@MainActor
final class TaskbarAddAppsTests: XCTestCase {
    private func tile(_ bundleID: String?, label: String?, type: String = "file-tile") -> [String: Any] {
        var data: [String: Any] = ["dock-extra": 0]
        if let bundleID { data["bundle-identifier"] = bundleID }
        if let label { data["file-label"] = label }
        return ["GUID": 1, "tile-data": data, "tile-type": type]
    }

    func testDockTilesBecomeAppsInTheDocksOrder() {
        let apps = DockApp.apps(fromDockTiles: [
            tile("com.apple.Safari", label: "Safari"),
            tile(nil, label: nil, type: "spacer-tile"),
            tile("us.mereader.app", label: "meReader"),
            // Listed twice: kept once, in its first place.
            tile("com.apple.Safari", label: "Safari"),
            // No label: the bundle identifier stands in.
            tile("com.example.nolabel", label: nil),
            tile("", label: "Empty"),
            ["tile-type": "file-tile"],
        ])
        XCTAssertEqual(apps, [
            DockApp(bundleID: "com.apple.Safari", name: "Safari"),
            DockApp(bundleID: "us.mereader.app", name: "meReader"),
            DockApp(bundleID: "com.example.nolabel", name: "com.example.nolabel"),
        ])
        XCTAssertEqual(DockApp.apps(fromDockTiles: []), [])
    }

    func testOnlyAppsAmongDroppedFilesCount() {
        let urls = [
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/Users/me/Documents/Notes.txt"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Mail.APP"),
            // The same app again, and an app with no bundle identifier.
            URL(fileURLWithPath: "/Volumes/Backup/Safari.app"),
            URL(fileURLWithPath: "/Applications/Broken.app"),
            URL(string: "https://example.com/Thing.app")!,
        ]
        let ids = TaskbarController.droppedApps(urls) { url in
            switch url.deletingPathExtension().lastPathComponent {
            case "Safari": "com.apple.Safari"
            case "Mail": "com.apple.mail"
            case "Thing": "com.example.thing"
            default: nil
            }
        }
        XCTAssertEqual(ids, ["com.apple.Safari", "com.apple.mail"])
        XCTAssertEqual(TaskbarController.droppedApps([]), [])
    }

    func testNoteIsAMenuLineThatCannotBeChosen() {
        let menu = TaskbarMenuBuilder.menu([
            .submenu("Add from Apple Dock", [.note("Every Apple Dock app is already here")]),
        ])
        let line = menu.items.first?.submenu?.items.first
        XCTAssertEqual(line?.title, "Every Apple Dock app is already here")
        XCTAssertEqual(line?.isEnabled, false)
        XCTAssertNil(line?.action)
    }
}
