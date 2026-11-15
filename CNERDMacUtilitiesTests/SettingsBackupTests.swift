import XCTest
@testable import CNERDMacUtilities

@MainActor
final class SettingsSnapshotTests: XCTestCase {
    private func makeSettings() -> (AppSettings, () -> Void) {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSettings(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    func testASnapshotBringsTheSameSetupToFreshSettings() {
        let (source, cleanUpSource) = makeSettings()
        let (target, cleanUpTarget) = makeSettings()
        defer { cleanUpSource(); cleanUpTarget() }

        source.greenButtonEnabled = true
        source.snappingEnabled = false
        source.shortcuts = [.maximize: KeyCombo(keyCode: 46, carbonModifiers: 4352, keyLabel: "M")]
        source.desktopSortOrder = DesktopSortOrder.allCases.last!
        source.taskbarEnabled = true
        source.taskbarPosition = .left
        source.taskbarIconPoints = 44
        source.taskbarCornerStyle = .rounded
        source.taskbarShowTrash = false
        source.taskbarPinnedApps = ["com.apple.Safari", "com.apple.mail"]
        source.taskbarAppOrder = ["com.apple.mail", "com.apple.Safari", "pid:123"]
        source.taskbarGroups = [TaskbarGroup(id: "g1", name: "Work", appIDs: ["com.apple.mail", "pid:123"])]
        source.taskbarGroupingEnabled = true
        source.taskbarHiddenApps = ["com.apple.Music"]
        source.taskbarDisplayRules = [
            TaskbarDisplayRule(displayKey: "KEY-A", displayName: "Side", mode: .chosenApps, appIDs: ["com.apple.Notes"], showsButtons: true),
        ]
        source.hasDonated = true

        let snapshot = source.snapshot()
        XCTAssertEqual(snapshot.taskbarAppOrder, ["com.apple.mail", "com.apple.Safari"], "An app known only by its process number does not travel")
        XCTAssertEqual(snapshot.taskbarGroups?.first?.appIDs, ["com.apple.mail"])

        target.apply(snapshot)
        XCTAssertEqual(target.snapshot(), snapshot)
        XCTAssertEqual(target.taskbarPosition, .left)
        XCTAssertEqual(target.shortcuts, source.shortcuts)
    }

    func testTheDockStateOfThisMacIsNotInASnapshot() throws {
        let (settings, cleanUp) = makeSettings()
        defer { cleanUp() }
        settings.taskbarTurnsDockOff = true
        settings.dockOffAgainAtLaunch = true
        let backup = SettingsBackup(appVersion: "1.3.0 (1)", exportedAt: Date(), settings: settings.snapshot())
        let text = String(decoding: try backup.encoded(), as: UTF8.self)
        XCTAssertFalse(text.lowercased().contains("dock"), "An import must never turn another Mac's Dock off")
    }

    func testMissingAndUnknownValuesLeaveSettingsAlone() {
        let (settings, cleanUp) = makeSettings()
        defer { cleanUp() }
        settings.taskbarPosition = .top
        settings.taskbarIconPoints = 30
        settings.finderEnabled = false

        var snapshot = SettingsSnapshot()
        snapshot.taskbarPosition = "diagonal"
        snapshot.taskbarIconPoints = 5000
        snapshot.shortcuts = ["notAnAction": KeyCombo(keyCode: 1, carbonModifiers: 256, keyLabel: "S")]
        settings.apply(snapshot)

        XCTAssertEqual(settings.taskbarPosition, .top, "A choice this version does not know is skipped")
        XCTAssertEqual(settings.taskbarIconPoints, TaskbarIconScale.clamped(5000), "A size out of range is brought into range")
        XCTAssertFalse(settings.finderEnabled, "A setting the file does not have stays as it is")
        XCTAssertEqual(settings.shortcuts, [:])
    }

    func testApplyingAnnouncesTheChangeOnce() {
        let (settings, cleanUp) = makeSettings()
        defer { cleanUp() }
        var snapshot = settings.snapshot()
        snapshot.taskbarPosition = "right"
        snapshot.taskbarShowTrash = false
        snapshot.snappingEnabled = false

        // The rest of the app must not react to a half-applied setup.
        let announced = expectation(forNotification: .appSettingsDidChange, object: nil)
        announced.expectedFulfillmentCount = 1
        announced.assertForOverFulfill = true
        settings.apply(snapshot)
        wait(for: [announced], timeout: 1)
    }
}

final class SettingsBackupFileTests: XCTestCase {
    private func backup(_ settings: SettingsSnapshot = SettingsSnapshot()) -> SettingsBackup {
        SettingsBackup(
            appVersion: "1.3.0 (12)", exportedAt: Date(timeIntervalSince1970: 1_800_000_000), computerName: "Office Mac",
            displays: [BackupDisplay(key: "KEY-MAIN", name: "Studio Display", isMain: true)], settings: settings
        )
    }

    func testAFileReadsBackTheSame() throws {
        var settings = SettingsSnapshot()
        settings.taskbarPinnedApps = ["com.apple.Safari"]
        settings.taskbarGroups = [TaskbarGroup(id: "g", name: "Web", appIDs: ["com.apple.Safari"])]
        let original = backup(settings)
        XCTAssertEqual(try SettingsBackup.decoded(from: original.encoded()), original)
    }

    func testAFileIsReadableText() throws {
        let text = String(decoding: try backup().encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"app\" : \"ai.cnerd.MacUtilities\""))
        XCTAssertTrue(text.contains("\"computerName\" : \"Office Mac\""))
    }

    func testOtherFilesAreRefused() {
        for text in ["", "not json", "{}", "{\"app\":\"some.other.app\",\"format\":1}", "[1,2,3]"] {
            XCTAssertThrowsError(try SettingsBackup.decoded(from: Data(text.utf8)), text) { error in
                XCTAssertEqual(error as? SettingsBackupError, .notASettingsFile)
            }
        }
    }

    func testAFileFromANewerFormatSaysSo() {
        let text = "{\"app\":\"ai.cnerd.MacUtilities\",\"format\":99,\"appVersion\":\"9.0.0 (500)\",\"somethingNew\":true}"
        XCTAssertThrowsError(try SettingsBackup.decoded(from: Data(text.utf8))) { error in
            XCTAssertEqual(error as? SettingsBackupError, .madeByNewerVersion("9.0.0 (500)"))
        }
    }

    func testAFileWithOnlyAFewSettingsStillReads() throws {
        let text = """
        {"app":"ai.cnerd.MacUtilities","format":1,"appVersion":"1.3.0 (12)","exportedAt":"2026-11-15T20:00:00Z",
         "settings":{"taskbarPosition":"left","settingFromTheFuture":42}}
        """
        let read = try SettingsBackup.decoded(from: Data(text.utf8))
        XCTAssertEqual(read.settings.taskbarPosition, "left")
        XCTAssertNil(read.settings.taskbarEnabled)
        XCTAssertNil(read.displays)
    }
}

/// Where a per-display setup lands on the Mac that imports it.
final class SettingsBackupDisplayTests: XCTestCase {
    private func display(_ key: String, _ name: String, main: Bool = false) -> BackupDisplay {
        BackupDisplay(key: key, name: name, isMain: main)
    }

    private func rule(_ key: String, _ name: String) -> TaskbarDisplayRule {
        TaskbarDisplayRule(displayKey: key, displayName: name, mode: .chosenApps, appIDs: ["com.apple.Notes"])
    }

    private let oldMac = [
        BackupDisplay(key: "OLD-MAIN", name: "Studio Display", isMain: true),
        BackupDisplay(key: "OLD-SIDE", name: "DELL U2720Q", isMain: false),
        BackupDisplay(key: "OLD-CAM", name: "Elgato", isMain: false),
    ]

    func testOnTheSameMacNothingMoves() {
        let rules = [rule("OLD-CAM", "Elgato"), rule("OLD-SIDE", "DELL U2720Q")]
        let placed = SettingsBackup.placing(rules, from: oldMac, on: oldMac)
        XCTAssertEqual(placed.rules, rules)
        XCTAssertEqual(placed.unmatched, [])
    }

    func testOnTheSameMacAnUnpluggedDisplayKeepsItsSetup() {
        let rules = [rule("OLD-CAM", "Elgato")]
        let placed = SettingsBackup.placing(rules, from: oldMac, on: Array(oldMac.prefix(2)))
        XCTAssertEqual(placed.rules, rules, "It must not move to another display of the same Mac")
        XCTAssertEqual(placed.unmatched, ["Elgato"])
    }

    func testOnAnotherMacADisplayWithTheSameNameGetsTheSetup() {
        let newMac = [display("NEW-MAIN", "Built-in Retina Display", main: true), display("NEW-CAM", "Elgato")]
        let placed = SettingsBackup.placing([rule("OLD-CAM", "Elgato")], from: oldMac, on: newMac)
        XCTAssertEqual(placed.rules.map(\.displayKey), ["NEW-CAM"])
        XCTAssertEqual(placed.unmatched, [])
    }

    func testOnAnotherMacTheSamePlaceInTheListIsNext() {
        let newMac = [display("NEW-MAIN", "Built-in Retina Display", main: true), display("NEW-SIDE", "LG UltraFine")]
        let placed = SettingsBackup.placing([rule("OLD-SIDE", "DELL U2720Q"), rule("OLD-CAM", "Elgato")], from: oldMac, on: newMac)
        XCTAssertEqual(placed.rules.map(\.displayKey), ["NEW-SIDE", "OLD-CAM"])
        XCTAssertEqual(placed.rules.first?.displayName, "LG UltraFine")
        XCTAssertEqual(placed.unmatched, ["Elgato"], "The new Mac has no third display")
    }

    func testTwoSetupsNeverLandOnOneDisplay() {
        let newMac = [display("NEW-MAIN", "Elgato", main: true)]
        let rules = [rule("OLD-MAIN", "Studio Display"), rule("OLD-CAM", "Elgato")]
        let placed = SettingsBackup.placing(rules, from: oldMac, on: newMac)
        XCTAssertEqual(Set(placed.rules.map(\.displayKey)).count, 2)
        XCTAssertEqual(placed.unmatched.count, 1)
    }
}

@MainActor
final class SettingsTransferTests: XCTestCase {
    func testAnImportCanBeUndone() throws {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cnerd-tests-\(UUID().uuidString)")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = AppSettings(defaults: defaults)
        settings.taskbarPosition = .bottom
        settings.taskbarPinnedApps = ["com.apple.Safari"]
        let transfer = SettingsTransferService(settings: settings, undoFolder: folder)
        XCTAssertFalse(transfer.canUndoImport)

        var incoming = SettingsSnapshot()
        incoming.taskbarPosition = "top"
        incoming.taskbarPinnedApps = ["com.apple.mail", "com.example.not-installed-anywhere"]
        let file = SettingsBackup(appVersion: "1.3.0 (12)", exportedAt: Date(), settings: incoming)
        let notice = transfer.apply(file)

        XCTAssertEqual(settings.taskbarPosition, .top)
        XCTAssertEqual(settings.taskbarPinnedApps, ["com.apple.mail", "com.example.not-installed-anywhere"])
        XCTAssertTrue(notice.text.contains("1 app in the file is not installed"), notice.text)
        XCTAssertTrue(transfer.canUndoImport)

        transfer.undoLastImport()
        XCTAssertEqual(settings.taskbarPosition, .bottom)
        XCTAssertEqual(settings.taskbarPinnedApps, ["com.apple.Safari"])
        XCTAssertFalse(transfer.canUndoImport)
    }

    func testTheTaskbarSwitchGoesThroughTheTaskbar() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.taskbarEnabled = true
        let transfer = SettingsTransferService(settings: settings, undoFolder: nil)
        var asked: [Bool] = []
        transfer.showTaskbar = { asked.append($0) }

        var incoming = SettingsSnapshot()
        incoming.taskbarEnabled = false
        transfer.apply(SettingsBackup(appVersion: "1.3.0 (12)", exportedAt: Date(), settings: incoming), savingUndo: false)
        XCTAssertEqual(asked, [false], "So the macOS Dock comes back when an import turns the taskbar off")
    }
}
