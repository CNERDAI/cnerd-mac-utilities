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
            + HiddenAppsIcon.allCases.map(\.symbolName)
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
        XCTAssertEqual(first.taskbarIconPoints, 26)
        XCTAssertEqual(first.taskbarNamePosition, .right)
        XCTAssertTrue(first.taskbarGlassBackground)
        first.taskbarPosition = .left
        first.taskbarIconPoints = 41
        first.taskbarNamePosition = .below
        first.taskbarGlassBackground = false

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.taskbarPosition, .left)
        XCTAssertEqual(second.taskbarIconPoints, 41)
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

final class TaskbarIconScaleTests: XCTestCase {
    func testSizeStaysInsideTheSliderRange() {
        XCTAssertEqual(TaskbarIconScale.clamped(5), 16)
        XCTAssertEqual(TaskbarIconScale.clamped(500), 72)
        XCTAssertEqual(TaskbarIconScale.clamped(33.6), 34)
    }

    /// Version 1.0 stored small, medium, or large. The slider starts at the size that choice had.
    @MainActor
    func testOldSizeChoiceCarriesOver() {
        XCTAssertEqual(TaskbarIconScale.points(forLegacySize: "small"), 20)
        XCTAssertEqual(TaskbarIconScale.points(forLegacySize: "medium"), 26)
        XCTAssertEqual(TaskbarIconScale.points(forLegacySize: "large"), 34)
        XCTAssertEqual(TaskbarIconScale.points(forLegacySize: nil), 26)

        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("large", forKey: AppSettings.Key.taskbarIconSize.rawValue)
        XCTAssertEqual(AppSettings(defaults: defaults).taskbarIconPoints, 34)
    }
}

final class AppTopicTests: XCTestCase {
    func testWellKnownAppsAreSortedByBundleIdentifier() {
        func topic(_ id: String, _ category: String? = nil) -> AppTopic {
            AppTopicClassifier.topic(bundleID: id, category: category)
        }
        XCTAssertEqual(topic("com.openai.chat"), .aiTools)
        XCTAssertEqual(topic("com.anthropic.claudefordesktop"), .aiTools)
        XCTAssertEqual(topic("com.google.Chrome", "public.app-category.productivity"), .browsers)
        XCTAssertEqual(topic("com.apple.Safari"), .browsers)
        XCTAssertEqual(topic("com.microsoft.Outlook", "public.app-category.productivity"), .communication)
        XCTAssertEqual(topic("com.microsoft.teams2"), .communication)
        XCTAssertEqual(topic("com.apple.Terminal", "public.app-category.utilities"), .developer)
        XCTAssertEqual(topic("com.apple.finder"), .utilities)
        XCTAssertEqual(topic("com.autodesk.fusion360"), .creative)
    }

    func testOtherAppsFollowTheCategoryTheyDeclare() {
        XCTAssertEqual(AppTopicClassifier.topic(bundleID: "com.example.editor", category: "public.app-category.developer-tools"), .developer)
        XCTAssertEqual(AppTopicClassifier.topic(bundleID: "com.example.chess", category: "public.app-category.board-games"), .games)
        XCTAssertEqual(AppTopicClassifier.topic(bundleID: "com.example.paint", category: "public.app-category.graphics-design"), .creative)
        XCTAssertEqual(AppTopicClassifier.topic(bundleID: "com.example.unknown", category: nil), .other)
        XCTAssertEqual(AppTopicClassifier.topic(bundleID: "com.example.unknown", category: "public.app-category.weather"), .other)
    }

    func testEveryTopicHasItsOwnGroup() {
        XCTAssertEqual(Set(AppTopic.allCases.map(\.groupID)).count, AppTopic.allCases.count)
        XCTAssertEqual(AppTopic.allCases.last, .other)
    }
}

final class TaskbarGroupingTests: XCTestCase {
    private let groups = [
        TaskbarGroup(id: "g1", name: "One", appIDs: ["a", "b", "c"]),
        TaskbarGroup(id: "g2", name: "Two", appIDs: ["d"]),
        TaskbarGroup(id: "g3", name: "Three", appIDs: []),
    ]

    private func topic(_ id: String) -> AppTopic {
        switch id.first {
        case "b": .browsers
        case "m": .communication
        default: .other
        }
    }

    func testSortingByTopicKeepsTopicOrderAndAppOrder() {
        let sorted = TaskbarGrouping.byTopic(["x1", "m1", "b1", "x2", "b2", "pid:9", "b1"], topic: topic)
        XCTAssertEqual(sorted.map(\.id), [AppTopic.browsers.groupID, AppTopic.communication.groupID, AppTopic.other.groupID])
        XCTAssertEqual(sorted.map(\.appIDs), [["b1", "b2"], ["m1"], ["x1", "x2"]])
        XCTAssertEqual(sorted.first?.name, "Browsers")
    }

    func testNewAppsJoinTheirTopicGroup() {
        var sorted = TaskbarGrouping.byTopic(["b1", "x1"], topic: topic)
        sorted[0].name = "Web"
        // b2 finds the renamed Browsers group. m1 gets a new group, placed ahead of Other.
        let added = TaskbarGrouping.adding(["b1", "b2", "m1", "pid:4"], to: sorted, topic: topic)
        XCTAssertEqual(added.map(\.name), ["Web", "Communication", "Other"])
        XCTAssertEqual(added.map(\.appIDs), [["b1", "b2"], ["m1"], ["x1"]])
        XCTAssertEqual(TaskbarGrouping.adding(["b1", "x1"], to: added, topic: topic), added)
    }

    func testNewAppsWaitInOtherWhenSortingIsOff() {
        let added = TaskbarGrouping.adding(["e", "a"], to: groups) { _ in .other }
        XCTAssertEqual(added.count, 4)
        XCTAssertEqual(added.last?.id, AppTopic.other.groupID)
        XCTAssertEqual(added.last?.appIDs, ["e"])
    }

    func testDraggingAnAppWithinAndAcrossGroups() {
        XCTAssertEqual(TaskbarGrouping.placing("c", before: true, target: "a", in: groups)[0].appIDs, ["c", "a", "b"])
        let across = TaskbarGrouping.placing("a", before: false, target: "d", in: groups)
        XCTAssertEqual(across.map(\.appIDs), [["b", "c"], ["d", "a"], []])
        // Repeating the same step changes nothing, and unknown apps are ignored.
        XCTAssertEqual(TaskbarGrouping.placing("a", before: false, target: "d", in: across), across)
        XCTAssertEqual(TaskbarGrouping.placing("zzz", before: true, target: "a", in: groups), groups)
        XCTAssertEqual(TaskbarGrouping.placing("a", before: true, target: "zzz", in: groups), groups)
        XCTAssertEqual(TaskbarGrouping.order(of: across), ["b", "c", "d", "a"])
    }

    func testMovingAnAppToAGroup() {
        XCTAssertEqual(TaskbarGrouping.moving("a", toGroup: "g3", in: groups).map(\.appIDs), [["b", "c"], ["d"], ["a"]])
        // Already in the group: it keeps its spot. A new app is simply added.
        XCTAssertEqual(TaskbarGrouping.moving("a", toGroup: "g1", in: groups), groups)
        XCTAssertEqual(TaskbarGrouping.moving("new", toGroup: "g2", in: groups)[1].appIDs, ["d", "new"])
        XCTAssertEqual(TaskbarGrouping.moving("pid:7", toGroup: "g2", in: groups), groups)
    }

    func testMovingGroups() {
        XCTAssertEqual(TaskbarGrouping.placingGroup("g1", at: "g3", in: groups).map(\.id), ["g2", "g3", "g1"])
        XCTAssertEqual(TaskbarGrouping.placingGroup("g3", at: "g1", in: groups).map(\.id), ["g3", "g1", "g2"])
        XCTAssertEqual(TaskbarGrouping.placingGroup("g1", at: "g1", in: groups), groups)
        XCTAssertEqual(TaskbarGrouping.shiftingGroup("g2", by: -1, in: groups).map(\.id), ["g2", "g1", "g3"])
        XCTAssertEqual(TaskbarGrouping.shiftingGroup("g2", by: 1, in: groups).map(\.id), ["g1", "g3", "g2"])
        XCTAssertEqual(TaskbarGrouping.shiftingGroup("g1", by: -1, in: groups), groups)
        XCTAssertEqual(TaskbarGrouping.shiftingGroup("g3", by: 1, in: groups), groups)
    }

    func testDeletingAGroupMovesItsAppsToOther() {
        let removed = TaskbarGrouping.removingGroup("g1", from: groups)
        XCTAssertEqual(removed.map(\.id), ["g2", "g3", AppTopic.other.groupID])
        XCTAssertEqual(removed.last?.appIDs, ["a", "b", "c"])
        XCTAssertEqual(TaskbarGrouping.removingGroup("g3", from: groups).map(\.id), ["g1", "g2"])
        // Other cannot be deleted while it holds apps.
        XCTAssertFalse(TaskbarGrouping.canRemoveGroup(AppTopic.other.groupID, from: removed))
        XCTAssertEqual(TaskbarGrouping.removingGroup(AppTopic.other.groupID, from: removed), removed)
    }

    func testNewGroupNamesAreUnique() {
        XCTAssertEqual(TaskbarGrouping.uniqueName("New Group", in: groups), "New Group")
        let named = groups + [TaskbarGroup(name: "New Group"), TaskbarGroup(name: "New Group 2")]
        XCTAssertEqual(TaskbarGrouping.uniqueName("New Group", in: named), "New Group 3")
    }

    @MainActor
    func testGroupSettingsPersist() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertFalse(first.taskbarGroupingEnabled, "Grouping must be opt-in")
        XCTAssertTrue(first.taskbarAutoGroupNewApps)
        XCTAssertEqual(first.taskbarGroups, [])
        first.taskbarGroupingEnabled = true
        first.taskbarAutoGroupNewApps = false
        first.taskbarGroups = groups

        let second = AppSettings(defaults: defaults)
        XCTAssertTrue(second.taskbarGroupingEnabled)
        XCTAssertFalse(second.taskbarAutoGroupNewApps)
        XCTAssertEqual(second.taskbarGroups, groups)
    }
}

final class HiddenAppsTests: XCTestCase {
    func testDraggingIntoAndInsideTheHiddenList() {
        // An app dropped next to a hidden app joins the hidden list at that spot.
        XCTAssertEqual(TaskbarOrdering.placingHidden("new", before: true, target: "b", in: ["a", "b"]), ["a", "new", "b"])
        XCTAssertEqual(TaskbarOrdering.placingHidden("new", before: false, target: "b", in: ["a", "b"]), ["a", "b", "new"])
        XCTAssertEqual(TaskbarOrdering.placingHidden("b", before: true, target: "a", in: ["a", "b"]), ["b", "a"])
        // Apps without a bundle identifier cannot be hidden, and the target must be hidden.
        XCTAssertEqual(TaskbarOrdering.placingHidden("pid:5", before: true, target: "a", in: ["a"]), ["a"])
        XCTAssertEqual(TaskbarOrdering.placingHidden("new", before: true, target: "zzz", in: ["a"]), ["a"])
    }

    func testPopUpGrowsFiveAppsWide() {
        let cell = TaskbarLayout.hiddenPopupCellSize(iconSize: 34)
        let one = TaskbarLayout.hiddenPopupSize(count: 1, iconSize: 34)
        let five = TaskbarLayout.hiddenPopupSize(count: 5, iconSize: 34)
        let six = TaskbarLayout.hiddenPopupSize(count: 6, iconSize: 34)
        XCTAssertEqual(one.width, cell.width + 2 * TaskbarLayout.hiddenPopupPadding)
        XCTAssertEqual(five.height, one.height)
        XCTAssertGreaterThan(five.width, one.width)
        // The sixth app starts a second row.
        XCTAssertEqual(six.width, five.width)
        XCTAssertEqual(six.height, 2 * cell.height + TaskbarLayout.hiddenPopupSpacing + 2 * TaskbarLayout.hiddenPopupPadding)
        XCTAssertEqual(TaskbarLayout.hiddenPopupSize(count: 0, iconSize: 34), one)
    }

    func testPopUpSitsNextToTheTaskbarAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 900)
        let size = CGSize(width: 200, height: 80)
        let gap = TaskbarLayout.hiddenPopupGap

        // Bottom taskbar: above the bar, centered on the button.
        let bottomBar = CGRect(x: 6, y: 6, width: 1488, height: 52)
        let middle = CGRect(x: 700, y: 11, width: 42, height: 42)
        let above = TaskbarLayout.hiddenPopupFrame(size: size, anchor: middle, bar: bottomBar, screen: screen, position: .bottom)
        XCTAssertEqual(above, CGRect(x: 621, y: 58 + gap, width: 200, height: 80))

        // A button at the far right: the pop-up is pushed back onto the screen.
        let farRight = CGRect(x: 1440, y: 11, width: 42, height: 42)
        let pushed = TaskbarLayout.hiddenPopupFrame(size: size, anchor: farRight, bar: bottomBar, screen: screen, position: .bottom)
        XCTAssertEqual(pushed.maxX, screen.maxX - gap)

        // Top taskbar: below the bar. Side taskbars: beside the bar.
        let topBar = CGRect(x: 0, y: 848, width: 1500, height: 52)
        let below = TaskbarLayout.hiddenPopupFrame(size: size, anchor: CGRect(x: 700, y: 853, width: 42, height: 42), bar: topBar, screen: screen, position: .top)
        XCTAssertEqual(below.maxY, topBar.minY - gap)
        let leftBar = CGRect(x: 0, y: 0, width: 52, height: 900)
        let beside = TaskbarLayout.hiddenPopupFrame(size: size, anchor: CGRect(x: 5, y: 20, width: 42, height: 42), bar: leftBar, screen: screen, position: .left)
        XCTAssertEqual(beside.minX, leftBar.maxX + gap)
        XCTAssertEqual(beside.minY, screen.minY + gap)
        let rightBar = CGRect(x: 1448, y: 0, width: 52, height: 900)
        let other = TaskbarLayout.hiddenPopupFrame(size: size, anchor: CGRect(x: 1453, y: 400, width: 42, height: 42), bar: rightBar, screen: screen, position: .right)
        XCTAssertEqual(other.maxX, rightBar.minX - gap)
    }

    func testBarSwitchTitlesNameTheOtherBar() {
        XCTAssertEqual(BarMode.taskbar.switchTitle, "Switch to Apple Dock")
        XCTAssertEqual(BarMode.appleDock.switchTitle, "Switch to Taskbar")
    }

    @MainActor
    func testHiddenAppSettingsPersist() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.taskbarHiddenApps, [])
        XCTAssertEqual(first.taskbarHiddenIcon, .sunglasses)
        XCTAssertFalse(first.taskbarTurnsDockOff)
        first.taskbarHiddenApps = ["com.apple.Notes", "com.apple.iCal"]
        first.taskbarHiddenIcon = .stack
        first.taskbarTurnsDockOff = true

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.taskbarHiddenApps, ["com.apple.Notes", "com.apple.iCal"])
        XCTAssertEqual(second.taskbarHiddenIcon, .stack)
        XCTAssertTrue(second.taskbarTurnsDockOff)
    }
}
