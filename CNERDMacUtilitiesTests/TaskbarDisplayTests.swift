import XCTest
@testable import CNERDMacUtilities

/// The per-display setup: which displays show only chosen apps, and which apps.
final class TaskbarDisplayRulesTests: XCTestCase {
    private let elgato = "KEY-ELGATO"
    private let side = "KEY-SIDE"

    func testADisplayWithoutARuleFollowsShowAppsOn() {
        XCTAssertNil(TaskbarDisplayRules.rule(for: elgato, in: []))
        XCTAssertFalse(TaskbarDisplayRules.showsChosenApps(elgato, in: []))
    }

    func testChoosingAModeMakesARuleAndGoingBackRemovesIt() {
        var rules = TaskbarDisplayRules.updating(elgato, name: "Elgato", in: []) { $0.mode = .chosenApps }
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(TaskbarDisplayRules.showsChosenApps(elgato, in: rules))
        XCTAssertEqual(rules.first?.displayName, "Elgato")
        XCTAssertEqual(rules.first?.showsButtons, false)

        rules = TaskbarDisplayRules.updating(elgato, name: "Elgato", in: rules) { $0.mode = .followScope }
        XCTAssertEqual(rules, [], "A rule that says nothing is not stored")
    }

    func testChosenAppsAreKeptWhenTheModeGoesBack() {
        var rules = TaskbarDisplayRules.updating(elgato, name: "Elgato", in: []) { $0.mode = .chosenApps }
        rules = TaskbarDisplayRules.adding(["a", "b"], to: elgato, name: "Elgato", in: rules)
        rules = TaskbarDisplayRules.updating(elgato, name: "Elgato", in: rules) { $0.mode = .followScope }
        XCTAssertFalse(TaskbarDisplayRules.showsChosenApps(elgato, in: rules))
        XCTAssertEqual(TaskbarDisplayRules.rule(for: elgato, in: rules)?.appIDs, ["a", "b"])
    }

    func testAddingSkipsAppsAlreadyThereAndAppsWithoutABundleIdentifier() {
        var rules = TaskbarDisplayRules.adding(["a", "b"], to: elgato, name: "Elgato", in: [])
        rules = TaskbarDisplayRules.adding(["b", "pid:42", "c"], to: elgato, name: "Elgato", in: rules)
        XCTAssertEqual(TaskbarDisplayRules.rule(for: elgato, in: rules)?.appIDs, ["a", "b", "c"])
    }

    func testRemovingTakesOneAppOffOneDisplay() {
        var rules = TaskbarDisplayRules.adding(["a", "b"], to: elgato, name: "Elgato", in: [])
        rules = TaskbarDisplayRules.adding(["a"], to: side, name: "Side", in: rules)
        rules = TaskbarDisplayRules.removing("a", from: elgato, in: rules)
        XCTAssertEqual(TaskbarDisplayRules.rule(for: elgato, in: rules)?.appIDs, ["b"])
        XCTAssertEqual(TaskbarDisplayRules.rule(for: side, in: rules)?.appIDs, ["a"])
        XCTAssertEqual(TaskbarDisplayRules.removing("zzz", from: elgato, in: rules), rules)
        XCTAssertEqual(TaskbarDisplayRules.removing("a", from: "KEY-UNKNOWN", in: rules), rules)
    }

    func testPlacingReordersAndIsSafeToRepeat() {
        let rules = TaskbarDisplayRules.adding(["a", "b", "c"], to: elgato, name: "Elgato", in: [])
        let moved = TaskbarDisplayRules.placing("c", before: true, target: "a", on: elgato, name: "Elgato", in: rules)
        XCTAssertEqual(TaskbarDisplayRules.rule(for: elgato, in: moved)?.appIDs, ["c", "a", "b"])
        let again = TaskbarDisplayRules.placing("c", before: true, target: "a", on: elgato, name: "Elgato", in: moved)
        XCTAssertEqual(again, moved)
        let after = TaskbarDisplayRules.placing("c", before: false, target: "b", on: elgato, name: "Elgato", in: moved)
        XCTAssertEqual(TaskbarDisplayRules.rule(for: elgato, in: after)?.appIDs, ["a", "b", "c"])
    }

    func testPlacingAnAppFromElsewhereAddsItNextToTheTarget() {
        let rules = TaskbarDisplayRules.adding(["a", "b"], to: elgato, name: "Elgato", in: [])
        let added = TaskbarDisplayRules.placing("new", before: false, target: "a", on: elgato, name: "Elgato", in: rules)
        XCTAssertEqual(TaskbarDisplayRules.rule(for: elgato, in: added)?.appIDs, ["a", "new", "b"])
        // Nothing to land next to, an app onto itself, and an app without a bundle identifier change nothing.
        XCTAssertEqual(TaskbarDisplayRules.placing("new", before: true, target: "zzz", on: elgato, name: "Elgato", in: rules), rules)
        XCTAssertEqual(TaskbarDisplayRules.placing("a", before: true, target: "a", on: elgato, name: "Elgato", in: rules), rules)
        XCTAssertEqual(TaskbarDisplayRules.placing("pid:7", before: true, target: "a", on: elgato, name: "Elgato", in: rules), rules)
    }

    func testOnlyDisplaysInChosenModeCountAsShowingAnApp() {
        var rules = TaskbarDisplayRules.adding(["a"], to: elgato, name: "Elgato", in: [])
        XCTAssertEqual(TaskbarDisplayRules.displays(showing: "a", in: rules), [], "The list is kept, but the mode is still Same as Show Apps On")
        rules = TaskbarDisplayRules.updating(elgato, name: "Elgato", in: rules) { $0.mode = .chosenApps }
        XCTAssertEqual(TaskbarDisplayRules.displays(showing: "a", in: rules), [elgato])
        XCTAssertEqual(TaskbarDisplayRules.displays(showing: "b", in: rules), [])
    }

    @MainActor
    func testRulesAreEmptyByDefaultAndPersist() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.taskbarDisplayRules, [])
        let rule = TaskbarDisplayRule(
            displayKey: elgato, displayName: "Elgato", mode: .chosenApps, appIDs: ["com.elgato.CameraHub"], showsButtons: true
        )
        first.taskbarDisplayRules = [rule]
        XCTAssertEqual(AppSettings(defaults: defaults).taskbarDisplayRules, [rule])
    }

    func testABarWithoutItsButtonsIsShorter() {
        var request = TaskbarFitRequest(
            barLength: 1000, isHorizontal: true, iconSize: 26, showNames: false, namePosition: .right,
            nameSize: 10, sectionCounts: [2]
        )
        let withButton = TaskbarFitting.length(request, iconSize: 26, showNames: false, visibleCount: 2, showsMore: false)
        request.showsApplicationsButton = false
        let without = TaskbarFitting.length(request, iconSize: 26, showNames: false, visibleCount: 2, showsMore: false)
        let button: CGFloat = 26 + 2 * TaskbarLayout.buttonPadding
        let line = 2 * TaskbarLayout.partSpacing + TaskbarLayout.separatorThickness
        XCTAssertEqual(withButton - without, button + line, accuracy: 0.001)
        // Two apps and the padding at both ends, nothing else.
        XCTAssertEqual(without, 2 * TaskbarLayout.barEndPadding + 2 * button + TaskbarLayout.appSpacing, accuracy: 0.001)
    }
}
