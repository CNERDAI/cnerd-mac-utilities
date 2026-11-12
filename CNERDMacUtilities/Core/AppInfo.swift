import Foundation

/// Static facts about the application.
enum AppInfo {
    static let name = "CNERD Mac Utilities"
    static let developer = "CNERD AI"
    static let websiteURL = URL(string: "https://cnerd.ai")!
    static let sourceURL = URL(string: "https://github.com/CNERDAI/cnerd-mac-utilities")!

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
