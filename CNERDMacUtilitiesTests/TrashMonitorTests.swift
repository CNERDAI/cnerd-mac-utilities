import AppKit
import XCTest
@testable import CNERDMacUtilities

final class TrashStateTests: XCTestCase {
    func testFinderAnswerDecidesWhenThereIsOne() {
        XCTAssertTrue(TrashMonitor.hasItems(finderCount: 3, dockSaysFull: false))
        XCTAssertFalse(TrashMonitor.hasItems(finderCount: 0, dockSaysFull: true), "Finder knows exactly, so a stale Dock note loses")
    }

    func testDockNoteDecidesWithoutFinder() {
        XCTAssertTrue(TrashMonitor.hasItems(finderCount: nil, dockSaysFull: true))
        XCTAssertFalse(TrashMonitor.hasItems(finderCount: nil, dockSaysFull: false))
    }

    func testMacOSHasBothTrashPictures() {
        XCTAssertNotNil(NSImage(named: NSImage.trashEmptyName), "The taskbar draws this for an empty Trash")
        XCTAssertNotNil(NSImage(named: NSImage.trashFullName), "The taskbar draws this for a Trash with items")
    }

    /// Runs only on a Mac where this app was already allowed to control Finder. It never shows
    /// the macOS prompt.
    func testFinderCountsTheTrashWhenAllowed() async throws {
        try XCTSkipUnless(FinderTrash.canAsk(), "This app has not been allowed to control Finder on this Mac")
        let count = await FinderTrash.itemCount()
        let answer = try XCTUnwrap(count, "Finder should answer the count question")
        XCTAssertGreaterThanOrEqual(answer, 0)
        let dockSaysFull = await DockInfo.trashIsFull
        print("Finder says the Trash holds \(answer) items. The Dock says full: \(dockSaysFull)")
    }
}
