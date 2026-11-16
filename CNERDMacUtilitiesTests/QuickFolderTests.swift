import AppKit
import XCTest
@testable import CNERDMacUtilities

final class QuickFolderRulesTests: XCTestCase {
    private let home = "/Users/pat"

    func testFoldersInsideHomeAreKeptWithATilde() {
        XCTAssertEqual(QuickFolders.storedPath("/Users/pat/Projects/Site/", home: home), "~/Projects/Site")
        XCTAssertEqual(QuickFolders.storedPath("/Users/pat", home: home), "~")
        XCTAssertEqual(QuickFolders.storedPath("/Volumes/Backup/Photos", home: home), "/Volumes/Backup/Photos")
        XCTAssertEqual(QuickFolders.storedPath("/Users/patricia/Work", home: home), "/Users/patricia/Work", "Another person's folder only looks alike")
    }

    func testAStoredPathFindsTheFolderOnAnotherMac() {
        XCTAssertEqual(QuickFolders.fullPath("~/Projects/Site", home: "/Users/sam"), "/Users/sam/Projects/Site")
        XCTAssertEqual(QuickFolders.fullPath("~", home: "/Users/sam"), "/Users/sam")
        XCTAssertEqual(QuickFolders.fullPath("/Volumes/Backup", home: "/Users/sam"), "/Volumes/Backup")
    }

    func testAFolderIsNeverListedTwice() {
        let builtIn = ["/Users/pat", "/Users/pat/Documents", "/Applications"]
        var stored = QuickFolders.adding(["/Users/pat/Projects", "/Users/pat/Documents", "/Applications/"], to: [], builtIn: builtIn, home: home)
        XCTAssertEqual(stored, ["~/Projects"], "The built-in folders are already in the list")
        stored = QuickFolders.adding(["/Users/pat/Projects/", "/Volumes/Backup"], to: stored, builtIn: builtIn, home: home)
        XCTAssertEqual(stored, ["~/Projects", "/Volumes/Backup"])
        XCTAssertEqual(QuickFolders.removing("~/Projects", from: stored), ["/Volumes/Backup"])
    }

    func testAnAddedFolderIsNamedAfterItsLastPart() {
        let folder = QuickFolder.custom(storedPath: "~/Projects/Client Sites", home: home)
        XCTAssertEqual(folder.title, "Client Sites")
        XCTAssertEqual(folder.url.path, "/Users/pat/Projects/Client Sites")
        XCTAssertTrue(folder.isCustom)
        XCTAssertFalse(QuickFolder.standard.contains { $0.isCustom })
    }
}

@MainActor
final class QuickFolderControllerTests: XCTestCase {
    private func makeController() -> (FinderController, AppSettings, () -> Void) {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        let controller = FinderController(settings: settings, permissions: PermissionsService())
        return (controller, settings, { defaults.removePersistentDomain(forName: suite) })
    }

    func testAddedFoldersFollowTheBuiltInOnesAndCanBeRemoved() throws {
        let (finder, settings, cleanUp) = makeController()
        defer { cleanUp() }
        let builtIn = finder.quickFolders.count
        XCTAssertGreaterThanOrEqual(builtIn, 5)

        finder.addFolders([URL(fileURLWithPath: "/Volumes/Backup/Photos"), URL(fileURLWithPath: "/Applications")])
        XCTAssertEqual(settings.finderQuickFolders, ["/Volumes/Backup/Photos"])
        let added = try XCTUnwrap(finder.quickFolders.last)
        XCTAssertEqual(finder.quickFolders.count, builtIn + 1)
        XCTAssertEqual(added.title, "Photos")

        finder.removeFolder(finder.quickFolders[0])
        XCTAssertEqual(finder.quickFolders.count, builtIn + 1, "A built-in folder cannot be removed")
        finder.removeFolder(added)
        XCTAssertEqual(settings.finderQuickFolders, [])
    }

    func testTheTaskbarMenuHasNoFoldersWhileFinderEnhancementsIsOff() {
        let (finder, settings, cleanUp) = makeController()
        defer { cleanUp() }
        XCTAssertFalse(finder.menuFolders.isEmpty)
        settings.finderEnabled = false
        XCTAssertTrue(finder.menuFolders.isEmpty, "A module that is off does nothing")
    }

    func testAddedFoldersTravelInASettingsFile() {
        let (finder, settings, cleanUp) = makeController()
        defer { cleanUp() }
        finder.addFolders([URL(fileURLWithPath: NSHomeDirectory() + "/Projects")])
        XCTAssertEqual(settings.snapshot().finderQuickFolders, ["~/Projects"])
    }

    func testAMenuLineWithAPictureRunsItsAction() throws {
        var opened = false
        let menu = TaskbarMenuBuilder.menu([
            .note("Quick Folders"),
            .item("Projects", symbol: "folder") { opened = true },
        ])
        XCTAssertEqual(menu.items.map(\.title), ["Quick Folders", "Projects"])
        let line = menu.items[1]
        XCTAssertNotNil(line.image, "The folder picture should show")
        _ = try XCTUnwrap(line.target).perform(try XCTUnwrap(line.action), with: line)
        XCTAssertTrue(opened)
    }
}
