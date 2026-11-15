import AppKit
import SwiftUI

/// Overview of the three modules plus a few key facts. Kept short on purpose.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SettingsPage(.dashboard) {
            Section {
                BrandHeader()
            }

            Section("Utilities") {
                ForEach(SidebarItem.modules) { item in
                    moduleRow(item)
                }
            }

            Section("Status") {
                LabeledContent("Accessibility Permission") {
                    if environment.permissions.isAccessibilityTrusted {
                        StatusBadge("Granted", level: .good)
                    } else {
                        StatusBadge("Not granted", level: .attention)
                    }
                }

                LabeledContent("Launch at Login") {
                    StatusBadge(
                        environment.loginItem.statusText,
                        level: environment.loginItem.isEnabled ? .good : (environment.loginItem.needsApproval ? .attention : .off)
                    )
                }
            }
        }
        .onAppear {
            environment.permissions.refreshAccessibility()
            environment.loginItem.refresh()
        }
    }

    private func moduleRow(_ item: SidebarItem) -> some View {
        HStack(spacing: 12) {
            TintedIcon(symbolName: item.symbolName, tint: item.tint, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                if let status = environment.status(for: item) {
                    StatusBadge(status)
                        .font(.subheadline)
                }
            }

            Spacer()

            Button("Open Settings") {
                environment.navigation.selection = item
            }
            .accessibilityLabel("Open \(item.title) settings")
        }
        .padding(.vertical, 4)
    }
}
