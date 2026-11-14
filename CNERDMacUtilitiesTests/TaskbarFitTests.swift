import XCTest
@testable import CNERDMacUtilities

/// Which taskbars an app shows on.
final class TaskbarAppScopeTests: XCTestCase {
    /// Three displays with a taskbar each. Display 1 is the main display.
    private let bars: [UInt32] = [1, 3, 4]

    func testAllTaskbarsShowsEveryAppEverywhere() {
        XCTAssertEqual(TaskbarAppScope.allTaskbars.bars(forAppOn: [3], bars: bars), [1, 3, 4])
        XCTAssertEqual(TaskbarAppScope.allTaskbars.bars(forAppOn: [], bars: bars), [1, 3, 4])
    }

    func testAppShowsOnlyWhereItsWindowsAre() {
        XCTAssertEqual(TaskbarAppScope.windowDisplayOnly.bars(forAppOn: [3], bars: bars), [3])
        XCTAssertEqual(TaskbarAppScope.windowDisplayOnly.bars(forAppOn: [3, 4], bars: bars), [3, 4])
    }

    func testAppWithNoWindowGoesToTheMainTaskbar() {
        XCTAssertEqual(TaskbarAppScope.windowDisplayOnly.bars(forAppOn: [], bars: bars), [1])
    }

    func testWindowOnADisplayWithoutATaskbarGoesToTheMainTaskbar() {
        XCTAssertEqual(TaskbarAppScope.windowDisplayOnly.bars(forAppOn: [9], bars: bars), [1])
        // Taskbars on the other displays only: the first of them stands in for the main taskbar.
        XCTAssertEqual(TaskbarAppScope.windowDisplayOnly.bars(forAppOn: [1], bars: [3, 4]), [3])
    }

    func testMainTaskbarCanShowEverything() {
        XCTAssertEqual(TaskbarAppScope.mainAndWindowDisplay.bars(forAppOn: [3], bars: bars), [1, 3])
        XCTAssertEqual(TaskbarAppScope.mainAndWindowDisplay.bars(forAppOn: [], bars: bars), [1])
    }

    func testASingleTaskbarShowsEverything() {
        XCTAssertEqual(TaskbarAppScope.windowDisplayOnly.bars(forAppOn: [3], bars: [4]), [4])
        XCTAssertEqual(TaskbarAppScope.windowDisplayOnly.bars(forAppOn: [3], bars: []), [])
    }

    @MainActor
    func testScopeIsAllTaskbarsByDefaultAndPersists() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.taskbarAppScope, .allTaskbars)
        first.taskbarAppScope = .windowDisplayOnly
        XCTAssertEqual(AppSettings(defaults: defaults).taskbarAppScope, .windowDisplayOnly)
    }
}

/// Which display a window belongs to.
final class WindowLocatorTests: XCTestCase {
    /// A laptop screen with a larger display to its right and a small one above it,
    /// in global display coordinates (y grows downward).
    private let displays: [(id: UInt32, frame: CGRect)] = [
        (1, CGRect(x: 0, y: 0, width: 1512, height: 982)),
        (3, CGRect(x: 1512, y: -98, width: 1920, height: 1080)),
        (4, CGRect(x: 327, y: -600, width: 1024, height: 600)),
    ]

    private func window(_ pid: pid_t, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> WindowLocator.Window {
        WindowLocator.Window(pid: pid, frame: CGRect(x: x, y: y, width: width, height: height))
    }

    func testEachWindowBelongsToTheDisplayShowingMostOfIt() {
        let found = WindowLocator.displaysByProcess(
            windows: [
                window(10, 208, 104, 920, 783),
                window(11, 1766, 45, 1674, 820),
                window(12, 400, -500, 600, 400),
                // Sits across the edge between displays 1 and 3, mostly on 3.
                window(13, 1400, 100, 400, 400),
            ],
            displays: displays
        )
        XCTAssertEqual(found, [10: [1], 11: [3], 12: [4], 13: [3]])
    }

    func testAnAppWithWindowsOnTwoDisplaysIsOnBoth() {
        let found = WindowLocator.displaysByProcess(
            windows: [window(10, 208, 104, 920, 783), window(10, 2000, 0, 500, 500)],
            displays: displays
        )
        XCTAssertEqual(found, [10: [1, 3]])
    }

    func testNoWindowsAndNoDisplaysGiveNothing() {
        XCTAssertTrue(WindowLocator.displaysByProcess(windows: [], displays: displays).isEmpty)
        XCTAssertTrue(WindowLocator.displaysByProcess(windows: [window(10, 0, 0, 500, 500)], displays: []).isEmpty)
    }
}

/// Fitting apps on a taskbar that is too short for them.
final class TaskbarFittingTests: XCTestCase {
    private func request(
        bar: CGFloat,
        horizontal: Bool = true,
        icon: CGFloat = 26,
        names: Bool = false,
        namePosition: TaskbarNamePosition = .right,
        sections: [Int],
        hidden: Bool = false,
        trash: Bool = false
    ) -> TaskbarFitRequest {
        TaskbarFitRequest(
            barLength: bar, isHorizontal: horizontal, iconSize: icon, showNames: names, namePosition: namePosition,
            nameSize: 10, sectionCounts: sections, showsHiddenButton: hidden, showsTrash: trash
        )
    }

    func testLengthCountsEveryPartOfTheBar() {
        // Applications (34) with 10 at each end, a line (17), five apps in two groups, a line and the Trash.
        let twoGroups = request(bar: 2000, sections: [2, 3], trash: true)
        XCTAssertEqual(TaskbarFitting.appsLength(twoGroups, iconSize: 26, showNames: false, visibleCount: 5), 5 * 34 + 1 + 5 * 4)
        XCTAssertEqual(TaskbarFitting.length(twoGroups, iconSize: 26, showNames: false, visibleCount: 5, showsMore: false), 313)
        // The More button adds its own width (never under 40 on a top or bottom bar) and one gap.
        // Hidden Apps adds a line and a button.
        XCTAssertEqual(TaskbarFitting.length(twoGroups, iconSize: 26, showNames: false, visibleCount: 5, showsMore: true), 313 + 8 + 40)
        XCTAssertEqual(TaskbarLayout.moreButtonLength(iconSize: 48, isHorizontal: true), 56)
        XCTAssertEqual(TaskbarLayout.moreButtonLength(iconSize: 16, isHorizontal: false), 24)
        let withHidden = request(bar: 2000, sections: [2, 3], hidden: true, trash: true)
        XCTAssertEqual(TaskbarFitting.length(withHidden, iconSize: 26, showNames: false, visibleCount: 5, showsMore: false), 313 + 17 + 34)
        // Only the apps that stay on the bar count, and a group with none of them adds no line.
        XCTAssertEqual(TaskbarFitting.appsLength(twoGroups, iconSize: 26, showNames: false, visibleCount: 2), 2 * 34 + 4)
        XCTAssertEqual(TaskbarFitting.appsLength(twoGroups, iconSize: 26, showNames: false, visibleCount: 0), 0)
    }

    func testABarWithRoomIsLeftAlone() {
        let fit = TaskbarFitting.fit(request(bar: 1512, names: true, sections: [4]))
        XCTAssertEqual(fit, TaskbarFit(iconSize: 26, showNames: true, visibleCount: 4))
    }

    func testNamesAreHiddenFirst() {
        // Ten apps with names beside the icons need 1587 points. Without names they need 447.
        let fit = TaskbarFitting.fit(request(bar: 1512, names: true, sections: [10]))
        XCTAssertEqual(fit, TaskbarFit(iconSize: 26, showNames: false, visibleCount: 10))
    }

    func testShortNamesTakeLessRoomThanLongOnes() {
        var short = request(bar: 1512, names: true, sections: [10])
        short.nameWidths = Array(repeating: 40, count: 10)
        XCTAssertEqual(TaskbarFitting.fit(short), TaskbarFit(iconSize: 26, showNames: true, visibleCount: 10))
    }

    func testIconsShrinkWhenHidingNamesIsNotEnough() {
        // Thirty apps at 40 points need 1641 points. At 20 points they need 1021.
        let fit = TaskbarFitting.fit(request(bar: 1024, icon: 40, names: true, sections: [30]))
        XCTAssertEqual(fit, TaskbarFit(iconSize: 20, showNames: false, visibleCount: 30))
    }

    func testAppsThatStillDoNotFitGoBehindTheMoreButton() {
        // Sixty apps do not fit on 1024 points even at the smallest size. 32 fit next to a More button.
        let fit = TaskbarFitting.fit(request(bar: 1024, sections: [60]))
        XCTAssertEqual(fit, TaskbarFit(iconSize: 16, showNames: false, visibleCount: 32))
    }

    func testIconsAlreadyAtTheSmallestSizeAreNotMadeBigger() {
        let fit = TaskbarFitting.fit(request(bar: 1024, icon: 16, sections: [60]))
        XCTAssertEqual(fit.iconSize, 16)
        XCTAssertEqual(fit.visibleCount, 32)
    }

    func testSideBarKeepsNamesBesideTheIcons() {
        // Names beside the icons make a side bar wider, not longer, so hiding them frees nothing.
        let fit = TaskbarFitting.fit(request(bar: 600, horizontal: false, names: true, sections: [30]))
        XCTAssertEqual(fit, TaskbarFit(iconSize: 16, showNames: true, visibleCount: 18))
    }

    func testSideBarHidesNamesStackedUnderTheIcons() {
        let fit = TaskbarFitting.fit(request(bar: 600, horizontal: false, names: true, namePosition: .below, sections: [12]))
        XCTAssertEqual(fit, TaskbarFit(iconSize: 26, showNames: false, visibleCount: 12))
    }

    func testAnEmptyBarAndATinyBarDoNotBreak() {
        XCTAssertEqual(TaskbarFitting.fit(request(bar: 1024, sections: [])).visibleCount, 0)
        XCTAssertEqual(TaskbarFitting.fit(request(bar: 20, sections: [5])).visibleCount, 0)
    }

    func testWhateverIsChosenAlwaysFitsTheBar() {
        for bar in stride(from: CGFloat(300), through: 2600, by: 230) {
            for count in [1, 7, 18, 40, 95] {
                for icon in [CGFloat(16), 26, 48, 72] {
                    for horizontal in [true, false] {
                        for namePosition in [TaskbarNamePosition.right, .below] {
                            let request = request(
                                bar: bar, horizontal: horizontal, icon: icon, names: true, namePosition: namePosition,
                                sections: [count / 2, count - count / 2], hidden: true, trash: true
                            )
                            let fit = TaskbarFitting.fit(request)
                            let all = fit.visibleCount == count
                            let length = TaskbarFitting.length(
                                request, iconSize: fit.iconSize, showNames: fit.showNames,
                                visibleCount: fit.visibleCount, showsMore: !all
                            )
                            XCTAssertLessThanOrEqual(fit.iconSize, icon)
                            XCTAssertGreaterThanOrEqual(fit.iconSize, 16)
                            XCTAssertLessThanOrEqual(fit.visibleCount, count)
                            if fit.visibleCount > 0 {
                                XCTAssertLessThanOrEqual(length, bar, "bar \(bar), \(count) apps, icon \(icon), horizontal \(horizontal), \(namePosition)")
                            }
                            // Nothing is hidden or shrunk while the bar has room for the settings as they are.
                            let asSet = TaskbarFitting.length(request, iconSize: icon, showNames: true, visibleCount: count, showsMore: false)
                            if asSet <= bar - TaskbarFitting.slack {
                                XCTAssertEqual(fit, TaskbarFit(iconSize: icon, showNames: true, visibleCount: count))
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Where this app's own logo is drawn so it matches the icons macOS supplies.
final class TaskbarIconBodyTests: XCTestCase {
    func testBodyIsCenteredWithTheStandardMargin() {
        let body = TaskbarLayout.iconBodyRect(in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        XCTAssertEqual(body.minX, 100, accuracy: 0.001)
        XCTAssertEqual(body.minY, 100, accuracy: 0.001)
        XCTAssertEqual(body.width, 824, accuracy: 0.001)
        XCTAssertEqual(body.height, 824, accuracy: 0.001)
    }

    func testBodyScalesWithTheCanvasAndKeepsItsOrigin() {
        let body = TaskbarLayout.iconBodyRect(in: CGRect(x: 10, y: 20, width: 256, height: 256))
        XCTAssertEqual(body.midX, 138, accuracy: 0.001)
        XCTAssertEqual(body.midY, 148, accuracy: 0.001)
        XCTAssertEqual(body.width, 206, accuracy: 0.001)
    }
}
