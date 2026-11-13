import Foundation

/// Static facts about the application.
enum AppInfo {
    static let name = "CNERD Mac Utilities"
    static let developer = "CNERD AI"
    static let websiteURL = URL(string: "https://cnerd.ai")!
    static let sourceURL = URL(string: "https://github.com/CNERDAI/cnerd-mac-utilities")!
    /// The logo artwork in the asset catalog, without the plate macOS adds around app icons.
    static let logoAssetName = "AppLogo"

    /// Shown under About. The longer version is TRADEMARKS.md in the repository.
    static let trademarkNotice = """
    CNERD, CNERD AI, CNERD Mac Utilities, and their logos are trademarks of CNERD AI. \
    The MIT license covers the source code, not these names and logos. \
    Mac, macOS, Finder, and Dock are trademarks of Apple Inc. \
    Windows is a trademark of Microsoft Corporation. \
    All other names, logos, and app icons shown in this app belong to their owners. \
    They appear with respect, only to describe what this app works with. \
    CNERD Mac Utilities is not affiliated with, endorsed by, or sponsored by Apple, Microsoft, or any other company.
    """

    /// Suggested donation amounts in US dollars.
    static let donationAmounts = [5, 10, 20, 50, 100]

    /// The CNERD shop page, told which app and amount the donation is for.
    static func donateURL(amount: Int) -> URL {
        var components = URLComponents(string: "https://cnerd.ai/shop/")!
        components.queryItems = [
            URLQueryItem(name: "donate", value: String(amount)),
            URLQueryItem(name: "app", value: "mac-utilities"),
        ]
        return components.url!
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDisplay: String { "\(version) (\(build))" }
}

/// Identifiers for SwiftUI window scenes.
enum WindowID {
    static let main = "main"
}
