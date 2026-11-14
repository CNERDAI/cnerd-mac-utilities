import XCTest
@testable import CNERDMacUtilities

/// The taskbar's own right-click menus: where they open, and how the items become a menu.
final class TaskbarMenuPlacementTests: XCTestCase {
    private let menu = CGSize(width: 200, height: 150)

    func testBottomBarMenuSitsJustAboveTheBar() {
        // A bar on a display above the main one: y starts at 988.
        let bar = CGRect(x: 333, y: 988, width: 1012, height: 68)
        let origin = TaskbarLayout.menuTopLeft(click: CGPoint(x: 500, y: 1020), bar: bar, menuSize: menu, position: .bottom)
        XCTAssertEqual(origin.x, 500)
        // The menu hangs down from its top left corner, so its bottom ends one gap above the bar.
        XCTAssertEqual(origin.y - menu.height, bar.maxY + TaskbarLayout.menuGap)
    }

    func testTopBarMenuHangsBelowTheBar() {
        let bar = CGRect(x: 6, y: 880, width: 1500, height: 68)
        let origin = TaskbarLayout.menuTopLeft(click: CGPoint(x: 300, y: 900), bar: bar, menuSize: menu, position: .top)
        XCTAssertEqual(origin, CGPoint(x: 300, y: bar.minY - TaskbarLayout.menuGap))
    }

    func testSideBarMenusOpenBesideTheBarAtThePointer() {
        let left = CGRect(x: 6, y: 6, width: 68, height: 900)
        XCTAssertEqual(
            TaskbarLayout.menuTopLeft(click: CGPoint(x: 40, y: 400), bar: left, menuSize: menu, position: .left),
            CGPoint(x: left.maxX + TaskbarLayout.menuGap, y: 400)
        )
        let right = CGRect(x: 1438, y: 6, width: 68, height: 900)
        let origin = TaskbarLayout.menuTopLeft(click: CGPoint(x: 1470, y: 400), bar: right, menuSize: menu, position: .right)
        XCTAssertEqual(origin.x + menu.width, right.minX - TaskbarLayout.menuGap)
        XCTAssertEqual(origin.y, 400)
    }
}

@MainActor
final class TaskbarMenuBuilderTests: XCTestCase {
    func testItemsBecomeMenuLinesInOrder() {
        var ran: [String] = []
        let menu = TaskbarMenuBuilder.menu([
            .button("Open") { ran.append("open") },
            .divider,
            .toggle("Keep in Taskbar", isOn: true) { ran.append("keep \($0)") },
            .submenu("Show on Display", [
                .toggle("Elgato", isOn: false) { ran.append("elgato \($0)") },
            ]),
        ])
        XCTAssertEqual(menu.items.map(\.title), ["Open", "", "Keep in Taskbar", "Show on Display"])
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].state, .on)
        XCTAssertEqual(menu.items[3].submenu?.items.map(\.title), ["Elgato"])
        XCTAssertEqual(menu.items[3].submenu?.items.first?.state, .off)

        // Choosing a line runs its action. A toggle gets the opposite of what it showed.
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 2)
        menu.items[3].submenu?.performActionForItem(at: 0)
        XCTAssertEqual(ran, ["open", "keep false", "elgato true"])
    }

    func testDividersAreTidiedAndEmptySubmenusLeftOut() {
        let menu = TaskbarMenuBuilder.menu([
            .divider,
            .button("One") {},
            .divider,
            .divider,
            .submenu("Empty", []),
            .button("Two") {},
            .divider,
        ])
        XCTAssertEqual(menu.items.map(\.title), ["One", "", "Two"])
        XCTAssertEqual(TaskbarMenuBuilder.menu([]).numberOfItems, 0)
        XCTAssertEqual(TaskbarMenuBuilder.menu([.divider]).numberOfItems, 0)
    }
}
