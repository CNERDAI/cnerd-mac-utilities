import SwiftUI

/// The CNERD AI logo as a link to the CNERD AI website. The asset has a dark version for light
/// backgrounds and a white version for dark backgrounds, and macOS picks the one that fits.
struct DeveloperLogoLink: View {
    /// Height in points. The width follows the logo's shape.
    var height: CGFloat = 22

    var body: some View {
        Link(destination: AppInfo.websiteURL) {
            Image(AppInfo.developerLogoAssetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
        }
        .buttonStyle(.plain)
        .help("Open the CNERD AI website")
        .accessibilityLabel("CNERD AI website")
    }
}

/// Who made the app, at a glance: the app's logo, name, and version on the left, the CNERD AI
/// logo on the right. Used at the top of the Dashboard and of About.
struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(AppInfo.logoAssetName)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppInfo.name)
                    .font(.title3.weight(.semibold))
                Text("Version \(AppInfo.versionDisplay)")
                    .foregroundStyle(.secondary)
                Text("Free and open source")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text("Developed by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DeveloperLogoLink(height: 24)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The full note on names, logos, and trademarks, behind the button under About.
struct TrademarkSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Names, Logos, and Trademarks")
                    .font(.title3.weight(.semibold))
                Spacer()
                DeveloperLogoLink(height: 20)
            }

            Text(AppInfo.trademarkNotice)
                .fixedSize(horizontal: false, vertical: true)

            Text("The code is open source under the Apache License 2.0. The logos and the app icon are not: they are copyright CNERD AI, all rights reserved. A changed version of this app needs its own name and its own artwork.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("License", destination: AppInfo.licenseURL)
                Link("Full Trademark Note", destination: AppInfo.trademarksURL)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
