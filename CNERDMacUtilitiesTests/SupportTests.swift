import AppKit
import XCTest
@testable import CNERDMacUtilities

final class AppLogoTests: XCTestCase {
    func testLogoArtworkIsInTheAssetCatalog() {
        XCTAssertNotNil(NSImage(named: AppInfo.logoAssetName), "The sidebar logo needs the AppLogo image set")
    }
}

@MainActor
final class SupporterSettingTests: XCTestCase {
    func testDonatedSwitchIsOffByDefaultAndPersists() {
        let suite = "ai.cnerd.MacUtilities.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertFalse(first.hasDonated, "Nobody is marked as a donor until they say so")
        first.hasDonated = true

        XCTAssertTrue(AppSettings(defaults: defaults).hasDonated)
    }
}

final class TrademarkNoticeTests: XCTestCase {
    func testNoticeNamesTheOwners() {
        let notice = AppInfo.trademarkNotice
        for phrase in ["CNERD AI", "Apple Inc.", "Microsoft Corporation", "belong to their owners", "not affiliated"] {
            XCTAssertTrue(notice.contains(phrase), "The trademark notice should say: \(phrase)")
        }
        XCTAssertFalse(notice.contains("\n"), "The notice is one paragraph")
    }
}
