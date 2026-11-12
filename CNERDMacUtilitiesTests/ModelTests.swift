import AppKit
import Carbon.HIToolbox
import XCTest
@testable import CNERDMacUtilities

final class KeyComboTests: XCTestCase {
    func testDisplayStringOrdersModifiers() {
        let combo = KeyCombo(
            keyCode: UInt32(kVK_ANSI_C),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
            keyLabel: "C"
        )
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘C")
    }

    func testDefaultShortcutsAreUniqueAndComplete() {
        let defaults = ShortcutAction.defaultShortcuts
        XCTAssertEqual(defaults.count, ShortcutAction.allCases.count)
        XCTAssertEqual(Set(defaults.values).count, defaults.count)
        XCTAssertEqual(ShortcutAction.maximize.defaultCombo.displayString, "⌃⌥↑")
        XCTAssertEqual(Set(ShortcutAction.allCases.map(\.hotKeyID)).count, ShortcutAction.allCases.count)
    }

    func testSpecialKeyLabels() {
        XCTAssertEqual(KeyCombo.label(forKeyCode: UInt32(kVK_LeftArrow), characters: nil), "←")
        XCTAssertEqual(KeyCombo.label(forKeyCode: UInt32(kVK_ANSI_M), characters: "m"), "M")
    }

    func testCodableRoundTrip() throws {
        let combo = ShortcutAction.left.defaultCombo
        let data = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), combo)
    }
}

final class DesktopItemTests: XCTestCase {
    private func item(_ name: String, kind: String, daysAgo: Double?) -> DesktopItem {
        DesktopItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            modified: daysAgo.map { Date(timeIntervalSinceNow: -$0 * 86_400) },
            isDirectory: false
        )
    }

    func testSorting() {
        let items = [
            item("Report 10.pdf", kind: "PDF Document", daysAgo: 5),
            item("notes.txt", kind: "Plain Text", daysAgo: 1),
            item("Report 2.pdf", kind: "PDF Document", daysAgo: nil),
        ]
        XCTAssertEqual(DesktopItem.sorted(items, by: .name).map(\.name), ["notes.txt", "Report 2.pdf", "Report 10.pdf"])
        XCTAssertEqual(DesktopItem.sorted(items, by: .kind).map(\.name), ["Report 2.pdf", "Report 10.pdf", "notes.txt"])
        XCTAssertEqual(DesktopItem.sorted(items, by: .dateModified).map(\.name), ["notes.txt", "Report 10.pdf", "Report 2.pdf"])
    }

    func testLoadReadsFolderWithoutChangingIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cnerd-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("a".utf8).write(to: folder.appendingPathComponent("visible.txt"))
        try Data("b".utf8).write(to: folder.appendingPathComponent(".hidden"))

        let items = try DesktopItem.load(from: folder)
        XCTAssertEqual(items.map(\.url.lastPathComponent), ["visible.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }
}

final class FinderPathTests: XCTestCase {
    @MainActor
    func testFolderPathsLoseTrailingSlash() {
        XCTAssertEqual(FinderController.cleanedPath("/Users/me/Documents/"), "/Users/me/Documents")
        XCTAssertEqual(FinderController.cleanedPath("/Users/me/file.txt"), "/Users/me/file.txt")
        XCTAssertEqual(FinderController.cleanedPath("/"), "/")
    }
}

final class SymbolTests: XCTestCase {
    /// Every SF Symbol name used by the app must exist on this macOS version.
    func testAllSymbolNamesExist() {
        let names = AppSymbol.all
            + SidebarItem.allCases.map(\.symbolName)
            + WindowPosition.allCases.map(\.symbolName)
            + QuickFolder.standard.map(\.symbolName)
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "Missing SF Symbol: \(name)")
        }
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testDefaultValues() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.windowManagerEnabled)
        XCTAssertTrue(settings.maximizeEnabled)
        XCTAssertFalse(settings.greenButtonEnabled, "The green button beta must be opt-in")
        XCTAssertEqual(settings.shortcuts, ShortcutAction.defaultShortcuts)
        XCTAssertEqual(settings.desktopSortOrder, .name)
    }

    func testValuesPersistAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        first.windowManagerEnabled = false
        first.desktopSortOrder = .dateModified
        first.shortcuts[.center] = nil
        first.shortcuts[.left] = KeyCombo(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: UInt32(cmdKey | optionKey), keyLabel: "H")

        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.windowManagerEnabled)
        XCTAssertEqual(second.desktopSortOrder, .dateModified)
        XCTAssertNil(second.shortcuts[.center])
        XCTAssertEqual(second.shortcuts[.left]?.displayString, "⌥⌘H")
        XCTAssertEqual(second.shortcuts[.maximize], ShortcutAction.maximize.defaultCombo)
    }
}

final class TaskbarModelTests: XCTestCase {
    func testDisplayModeChoosesTheRightScreens() {
        XCTAssertEqual((0..<3).filter(TaskbarDisplayMode.allDisplays.includes), [0, 1, 2])
        XCTAssertEqual((0..<3).filter(TaskbarDisplayMode.mainDisplayOnly.includes), [0])
        XCTAssertEqual((0..<3).filter(TaskbarDisplayMode.otherDisplaysOnly.includes), [1, 2])
    }

    func testDockPositionMatchesDockPreferenceValues() {
        XCTAssertEqual(DockPosition.allCases.map(\.rawValue), ["left", "bottom", "right"])
    }

    @MainActor
    func testDockSizeConversion() {
        XCTAssertEqual(TaskbarController.dockSize(fromTileSize: 16), 0)
        XCTAssertEqual(TaskbarController.dockSize(fromTileSize: 128), 1)
        XCTAssertEqual(TaskbarController.dockSize(fromTileSize: 51), 0.3125, accuracy: 0.0001)
        XCTAssertEqual(TaskbarController.dockSize(fromTileSize: 500), 1)
    }

    @MainActor
    func testTaskbarIsOffByDefault() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.taskbarEnabled)
        XCTAssertEqual(settings.taskbarDisplayMode, .allDisplays)
        XCTAssertTrue(settings.taskbarReserveSpace)
    }
}

final class TaskbarLayoutTests: XCTestCase {
    /// A display's usable area in AppKit coordinates: 1440 x 805, starting 70 pt above the bottom.
    private let usable = CGRect(x: 0, y: 70, width: 1440, height: 805)

    func testFrameForEachEdge() {
        XCTAssertEqual(TaskbarLayout.frame(in: usable, position: .bottom, thickness: 44), CGRect(x: 0, y: 70, width: 1440, height: 44))
        XCTAssertEqual(TaskbarLayout.frame(in: usable, position: .top, thickness: 44), CGRect(x: 0, y: 831, width: 1440, height: 44))
        XCTAssertEqual(TaskbarLayout.frame(in: usable, position: .left, thickness: 60), CGRect(x: 0, y: 70, width: 60, height: 805))
        XCTAssertEqual(TaskbarLayout.frame(in: usable, position: .right, thickness: 60), CGRect(x: 1380, y: 70, width: 60, height: 805))
    }

    func testInsetsLeaveTheRestOfTheScreen() {
        for position in TaskbarPosition.allCases {
            let bar = TaskbarLayout.frame(in: usable, position: position, thickness: 50)
            let rest = TaskbarLayout.insets(position: position, thickness: 50).applied(toAppKitRect: usable)
            XCTAssertTrue(bar.intersection(rest).isEmpty || bar.intersection(rest).width == 0 || bar.intersection(rest).height == 0, "\(position) overlaps")
            XCTAssertEqual(bar.width * bar.height + rest.width * rest.height, usable.width * usable.height, accuracy: 0.5)
        }
    }

    func testInsetsNeverRemoveMoreThanHalf() {
        let rest = ScreenInsets(bottom: 5000).applied(toAppKitRect: usable)
        XCTAssertEqual(rest.height, usable.height / 2)
        XCTAssertEqual(ScreenInsets.zero.applied(toAppKitRect: usable), usable)
    }

    func testThicknessGrowsWithContent() {
        func thickness(_ position: TaskbarPosition, names: Bool, _ namePosition: TaskbarNamePosition = .right, icon: CGFloat = 26) -> CGFloat {
            TaskbarLayout.thickness(position: position, iconSize: icon, showNames: names, namePosition: namePosition)
        }
        // Top and bottom: names beside the icon do not change the height. Stacked names do.
        XCTAssertEqual(thickness(.bottom, names: false), 44)
        XCTAssertEqual(thickness(.bottom, names: true, .right), 44)
        XCTAssertGreaterThan(thickness(.top, names: true, .below), 44)
        XCTAssertGreaterThan(thickness(.bottom, names: false, icon: 34), thickness(.bottom, names: false, icon: 20))
        // Left and right: names beside the icon need the most width.
        XCTAssertEqual(thickness(.left, names: false), 44)
        XCTAssertGreaterThan(thickness(.left, names: true, .above), thickness(.left, names: false))
        XCTAssertGreaterThan(thickness(.right, names: true, .left), thickness(.right, names: true, .above))
    }

    @MainActor
    func testNewTaskbarSettingsPersist() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.taskbarPosition, .bottom)
        XCTAssertEqual(first.taskbarIconSize, .medium)
        XCTAssertEqual(first.taskbarNamePosition, .right)
        XCTAssertTrue(first.taskbarGlassBackground)
        first.taskbarPosition = .left
        first.taskbarIconSize = .large
        first.taskbarNamePosition = .below
        first.taskbarGlassBackground = false

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.taskbarPosition, .left)
        XCTAssertEqual(second.taskbarIconSize, .large)
        XCTAssertEqual(second.taskbarNamePosition, .below)
        XCTAssertFalse(second.taskbarGlassBackground)
    }

    func testWebsiteLink() {
        XCTAssertEqual(AppInfo.websiteURL.absoluteString, "https://cnerd.ai")
    }
}

final class TaskbarOrderingTests: XCTestCase {
    func testNewAppsAreAddedToTheEndOnce() {
        let order = TaskbarOrdering.merged(order: ["a", "b"], adding: ["b", "c", "pid:42", "c", "d"])
        XCTAssertEqual(order, ["a", "b", "c", "d"])
    }

    func testVisibleAppsFollowTheSavedOrder() {
        let visible = TaskbarOrdering.visible(order: ["a", "b", "c", "d"], pinned: ["d"], running: ["c", "pid:42", "a"])
        // b is neither kept nor running. d is kept but not running. pid:42 has no saved spot, so it goes last.
        XCTAssertEqual(visible, ["a", "c", "d", "pid:42"])
    }

    func testDraggingPlacesAnAppBeforeOrAfterTheTarget() {
        let order = ["a", "b", "c", "d"]
        XCTAssertEqual(TaskbarOrdering.placing("a", before: false, target: "c", in: order), ["b", "c", "a", "d"])
        XCTAssertEqual(TaskbarOrdering.placing("a", before: true, target: "c", in: order), ["b", "a", "c", "d"])
        XCTAssertEqual(TaskbarOrdering.placing("d", before: true, target: "b", in: order), ["a", "d", "b", "c"])
        XCTAssertEqual(TaskbarOrdering.placing("d", before: true, target: "a", in: order), ["d", "a", "b", "c"])
        XCTAssertEqual(TaskbarOrdering.placing("a", before: true, target: "a", in: order), order)
        XCTAssertEqual(TaskbarOrdering.placing("zzz", before: true, target: "a", in: order), order)
    }

    func testRepeatingTheSameDragStepChangesNothing() {
        let once = TaskbarOrdering.placing("d", before: true, target: "b", in: ["a", "b", "c", "d"])
        XCTAssertEqual(TaskbarOrdering.placing("d", before: true, target: "b", in: once), once)
        // Already in place: the app directly before its target stays put.
        XCTAssertEqual(TaskbarOrdering.placing("a", before: true, target: "b", in: ["a", "b", "c"]), ["a", "b", "c"])
    }

    func testRoundedTaskbarFloatsInsideTheScreenEdge() {
        let usable = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let margin = TaskbarLayout.floatingMargin
        let frame = TaskbarLayout.frame(in: usable, position: .bottom, thickness: 44, floating: true)
        XCTAssertEqual(frame, CGRect(x: margin, y: 70 + margin, width: 1440 - 2 * margin, height: 44))
        XCTAssertEqual(TaskbarLayout.insets(position: .bottom, thickness: 44, floating: true).bottom, 44 + 2 * margin)
        let side = TaskbarLayout.frame(in: usable, position: .right, thickness: 50, floating: true)
        XCTAssertEqual(side.maxX, usable.maxX - margin)
    }

    func testNameSizeChangesTheBar() {
        func thickness(_ position: TaskbarPosition, _ namePosition: TaskbarNamePosition, size: CGFloat) -> CGFloat {
            TaskbarLayout.thickness(position: position, iconSize: 26, showNames: true, namePosition: namePosition, nameSize: size)
        }
        XCTAssertGreaterThan(thickness(.bottom, .below, size: 14), thickness(.bottom, .below, size: 9))
        XCTAssertGreaterThan(thickness(.left, .right, size: 14), thickness(.left, .right, size: 9))
        // Names beside the icon never change the height of a top or bottom bar.
        XCTAssertEqual(thickness(.bottom, .right, size: 14), thickness(.bottom, .right, size: 9))
    }

    @MainActor
    func testKeptAppsAndOrderPersist() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.taskbarPinnedApps, [])
        XCTAssertEqual(first.taskbarCornerStyle, .square)
        XCTAssertTrue(first.taskbarShowTrash)
        first.taskbarPinnedApps = ["com.apple.Safari"]
        first.taskbarAppOrder = ["com.apple.finder", "com.apple.Safari"]
        first.taskbarCornerStyle = .rounded
        first.taskbarNameSize = .extraSmall

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.taskbarPinnedApps, ["com.apple.Safari"])
        XCTAssertEqual(second.taskbarAppOrder, ["com.apple.finder", "com.apple.Safari"])
        XCTAssertEqual(second.taskbarCornerStyle, .rounded)
        XCTAssertEqual(second.taskbarNameSize, .extraSmall)
    }
}
